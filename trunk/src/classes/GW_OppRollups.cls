public with sharing class GW_OppRollups {
/*-----------------------------------------------------------------------------------------------
* Written by Evan Callahan, copyright (c) 2010 Groundwire
* This program is released under the GNU General Public License. http://www.gnu.org/licenses/
* 
* This class calculates opportunity totals on accounts, contacts, and households.
*
* TO DO:
*   - special case totals for specified record types (so they have their own annual totals)
-----------------------------------------------------------------------------------------------*/

	// settings
	boolean triggerRollupEnabled = true; 
	set<id> recordTypesToExcludeAccts = new set<id>();
	set<id> recordTypesToExcludeCons = new set<id>();
	set<string> oppTypesToExcludeAccts = new set<string>();
	set<string> oppTypesToExcludeCons = new set<string>();	
	
	// set this to limit contact totals to opps with a specific 'bucket' account
	final string defaultAccountId = ONEN_DefaultAccount.getIndividualAccountId();

	static boolean isTest = false;

	// constructor
	public GW_OppRollups() {
	
		// load settings
        OppRollupSettings__c rollupSettings = OppRollupSettings__c.getInstance();

		if (rollupSettings != null) {
			if (rollupSettings.Excluded_Contact_Opp_Rectypes__c != null) {
				set<string> rtNamesToExclude = new set<string>(rollupSettings.Excluded_Contact_Opp_Rectypes__c.split(';'));
				recordTypesToExcludeCons = GW_RecTypes.GetRecordTypeIdSet('Opportunity', rtNamesToExclude);
			}
			if (rollupSettings.Excluded_Account_Opp_Rectypes__c != null) {
				set<string> rtNamesToExclude = new set<string>(rollupSettings.Excluded_Account_Opp_Rectypes__c.split(';'));
				recordTypesToExcludeAccts = GW_RecTypes.GetRecordTypeIdSet('Opportunity', rtNamesToExclude);
			}
			if (rollupSettings.Excluded_Contact_Opp_Types__c != null) {
				oppTypesToExcludeCons = new set<string>(rollupSettings.Excluded_Contact_Opp_Types__c.split(';'));
			}
			if (rollupSettings.Excluded_Account_Opp_Types__c != null) {
				oppTypesToExcludeAccts = new set<string>(rollupSettings.Excluded_Contact_Opp_Types__c.split(';'));
			}
			if (rollupSettings.Enable_Opp_Rollup_Triggers__c == false && !isTest)
				triggerRollupEnabled = false;
		}
		if (isTest) oppTypesToExcludeCons.add('In-Kind');
	}			

	public void rollupAccount( id aid ) {
	// roll up a single account's opps
		
		map<id, account> amap = new map<id, account>(
			[select id, TotalOppAmount__c, OppAmountThisYear__c, OppAmountLastNDays__c, 
				LastCloseDate__c, NumberOfClosedOpps__c  
				from account where id = : aid ]);
		
		if (!amap.isEmpty()) 
			rollupAccounts( amap );
	}

	@future
	public static void rollupAccountsFuture( set<id> acctIds ) {
	// roll up a single account's opps
		
		if (acctIds != null && !acctIds.isEmpty()) { 
			map<id, account> amap = new map<id, account>(
				[select id, TotalOppAmount__c, OppAmountThisYear__c, OppAmountLastNDays__c, 
					LastCloseDate__c, NumberOfClosedOpps__c  
					from account where id in :acctIds ]);
			
			GW_OppRollups rg = new GW_OppRollups();
			rg.rollupAccounts( amap );
		}
	}

	public void rollupAccounts( list<account> accts ) {
	// roll up opps for a set of accounts

		if (accts != null && !accts.isEmpty()) {
			rollupAccounts( new map<id, account>(accts) );
		}
	}

	public void rollupAccounts( map<id, account> amap ) {
	// roll up opps for a map of accounts
	// only accounts that have changed will get updated 

		// copy the accounts to a map of zerod out versions
		map<id, account> accountsToUpdate = new map<id, account>();
		set<id> allAccts = amap.keyset();
		for (id aid : allAccts) {
		 	accountsToUpdate.put(aid, new Account(id = aid, TotalOppAmount__c = 0, AverageAmount__c = 0, 
				SmallestAmount__c = 0, LargestAmount__c = 0, FirstCloseDate__c = null, 
				LastCloseDate__c = null, NumberOfClosedOpps__c = 0, OppAmountThisYear__c = 0, 
				OppsClosedThisYear__c = 0, OppAmountLastYear__c = 0, OppsClosedLastYear__c = 0,
				OppsClosed2YearsAgo__c = 0, OppAmount2YearsAgo__c = 0,
				OppsClosedLastNDays__c = 0, OppAmountLastNDays__c = 0
			));
		}

		// exclude the individual account if it has too many opps
		if (allAccts.contains(defaultAccountId) && amap.get(defaultAccountId).NumberOfClosedOpps__c > 3000)
			allAccts.remove(defaultAccountId);

		// copy all the rollups from each result row into the account objects
		integer startYear = system.today().year() - 2;
		for (sobject r : 
			[SELECT accountId, Calendar_Year(CloseDate) CalendarYr, 
	        	SUM(Amount) TotalOppAmount, AVG(Amount) AverageAmount, MIN(Amount) SmallestAmount,
				MAX(Amount) LargestAmount, MIN(CloseDate) FirstCloseDate, MAX(CloseDate) LastCloseDate, 
				COUNT_DISTINCT(Id) NumberOfClosedOpps FROM Opportunity
	    		WHERE isWon=true 
	    		AND (Amount > 0 OR Amount < 0) 
		    	AND RecordTypeId NOT IN : recordTypesToExcludeAccts
		    	AND Type NOT IN : oppTypesToExcludeAccts
		    	AND accountId IN : allAccts
				GROUP BY ROLLUP (accountId, Calendar_Year(closeDate))
	    		HAVING ( Calendar_Year(closeDate) = null OR Calendar_Year(closeDate) >= : startYear )
	    		AND accountId != null ] ) {
			//system.debug('ROLLUP ROW: ' + r);

			// get the account id for this result row
			id aid = (id)(r.get('accountId'));
	
			// copy all the rollups from this result row into the account object	
			updateRollupFromResult((sobject)(accountsToUpdate.get(aid)), r);
		}

		// also do rollups for last N days
		for (sobject r : 
			[SELECT accountId, 
		    	SUM(Amount) TotalOppAmount, COUNT_DISTINCT(Id) NumberOfClosedOpps
		    	FROM Opportunity 
		    	WHERE isWon=true 
		    	AND (Amount > 0 OR Amount < 0) 
		    	AND RecordTypeId NOT IN : recordTypesToExcludeAccts
		    	AND Type NOT IN : oppTypesToExcludeAccts
		    	AND accountId IN : allAccts
		    	AND closeDate >= LAST_N_DAYS:365
				GROUP BY accountId
				HAVING accountId != null ] ) {
			//system.debug('ROLLUP ROW: ' + r);
			
			// get the ids
			id aid = (id)(r.get('accountId'));
				
			// process the result row, copying it into the contact record(s)
			updateRollupFromResultLastNDays((sobject)(accountsToUpdate.get(aid)), r);
		}

		// remove any records that have not changed
		for (id aid : allAccts) {
			account a1 = amap.get(aid);
			account a2 = accountsToUpdate.get(aid);
			if (a1.TotalOppAmount__c == a2.TotalOppAmount__c && 
					a1.OppAmountThisYear__c == a2.OppAmountThisYear__c &&
					a1.OppAmountLastNDays__c == a2.OppAmountLastNDays__c &&
					a1.LastCloseDate__c == a2.LastCloseDate__c)
				accountsToUpdate.remove(aid);
		}
		
		// update all the accounts from this batch 
		update accountsToUpdate.values();
	}

	public void rollupContact( id cid ) {
		// roll up opps for one contact
		list<contact> cc = [select id, onen_household__c, TotalOppAmount__c, OppAmountThisYear__c, OppAmountLastNDays__c, 
				onen_household__r.TotalOppAmount__c, onen_household__r.OppAmountThisYear__c, onen_household__r.OppAmountLastNDays__c, 
				onen_household__r.LastCloseDate__c, onen_household__r.NumberOfClosedOpps__c,
				LastCloseDate__c, NumberOfClosedOpps__c	from contact where id = :cid ];
	
		if (!cc.isEmpty()) { 
			map<id, onen_household__c> hhmap = new map<id, onen_household__c>();
			if (cc[0].onen_household__c != null) 
				hhmap.put(cc[0].onen_household__c, cc[0].onen_household__r);
		
			rollupContacts( new map<id, contact>( cc ), hhmap );
		}
	}

	public void rollupHousehold( id hhid ) {
		// roll up opps for one household
		list<onen_household__c> hhs = [select id, TotalOppAmount__c, OppAmountThisYear__c, 
			OppAmountLastNDays__c, LastCloseDate__c, NumberOfClosedOpps__c 
			from onen_household__c where id = :hhid ];
		
		if (!hhs.isEmpty()) 
			rollupHouseholds( hhs );
	}	

	public void rollupHouseholds( list<onen_household__c> hhs ) {
	// roll up opps for households

		if (hhs != null && !hhs.isEmpty()) {
			
			map<id, onen_household__c> hhmap = new map<id, onen_household__c>( hhs );
		
			// get household contacts
			map<id, contact> cmap = new map<id, contact>([select id, onen_household__c, LastCloseDate__c, 
				OppAmountThisYear__c, NumberOfClosedOpps__c, TotalOppAmount__c, 
				OppAmountLastNDays__c from contact where onen_household__c in :hhmap.keyset() ]);
			
			// roll up totals
			rollupContacts( cmap, hhmap );
		}
	}
	
	@future
	public static void rollupHouseholdsFuture( set<id> hhIds ) {	
		if (hhIds != null && !hhIds.isEmpty()) {

			// get household contacts
			map<id, contact> cmap = new map<id, contact>([select id, onen_household__c, LastCloseDate__c, 
				OppAmountThisYear__c, NumberOfClosedOpps__c, TotalOppAmount__c, OppAmountLastNDays__c, 
				onen_household__r.LastCloseDate__c, onen_household__r.OppAmountThisYear__c, 
				onen_household__r.NumberOfClosedOpps__c, onen_household__r.TotalOppAmount__c, 
				onen_household__r.OppAmountLastNDays__c from contact where onen_household__c in :hhIds ]);
			
			map<id, onen_household__c> hhmap = new map<id, onen_household__c>();
			for (contact c : cmap.values())
				hhmap.put(c.onen_household__c, c.onen_household__r);
			
			// roll up totals
			GW_OppRollups rg = new GW_OppRollups();
			rg.rollupContacts( cmap, hhmap );
		}
	}

	public void rollupContacts( map<id, contact> cmap, map<id, onen_household__c> hhmap ) {
	// roll up opps for a list of contacts and their households

		set<id> conIds = cmap.keySet();
		set<id> hhIds = hhmap.keySet();

		// copy the contacts and households to a map of zerod out versions
		map<id, contact> contactsToUpdate = new map<id, contact>();
		map<id, onen_household__c> householdsToUpdate = new map<id, onen_household__c>();
		for (id cid : conIds) {
		 	contactsToUpdate.put(cid, new Contact(id = cid, TotalOppAmount__c = 0, AverageAmount__c = 0, 
				SmallestAmount__c = 0, LargestAmount__c = 0, FirstCloseDate__c = null, 
				LastCloseDate__c = null, NumberOfClosedOpps__c = 0, OppAmountThisYear__c = 0, 
				OppsClosedThisYear__c = 0, OppAmountLastYear__c = 0, OppsClosedLastYear__c = 0,
				OppsClosed2YearsAgo__c = 0, OppAmount2YearsAgo__c = 0, 
				OppsClosedLastNDays__c = 0, OppAmountLastNDays__c = 0
			));
		}
		for (id hhid : hhIds) {
		 	householdsToUpdate.put(hhid, new onen_household__c(id = hhid, TotalOppAmount__c = 0, AverageAmount__c = 0, 
				SmallestAmount__c = 0, LargestAmount__c = 0, FirstCloseDate__c = null, 
				LastCloseDate__c = null, NumberOfClosedOpps__c = 0, OppAmountThisYear__c = 0, 
				OppsClosedThisYear__c = 0, OppAmountLastYear__c = 0, OppsClosedLastYear__c = 0,
				OppsClosed2YearsAgo__c = 0, OppAmount2YearsAgo__c = 0, 
				OppsClosedLastNDays__c = 0, OppAmountLastNDays__c = 0
			));
		}

		// copy all the rollups from each result row into the contact objects
		integer startYear = system.today().year() - 2;
		for (sobject r : 
			[SELECT contact.ONEN_household__c hhid, contactId, Calendar_Year(Opportunity.CloseDate) CalendarYr, 
		    	SUM(Opportunity.Amount) TotalOppAmount,
		    	AVG(Opportunity.Amount) AverageAmount, MIN(Opportunity.Amount) SmallestAmount,
		    	MAX(Opportunity.Amount) LargestAmount, MIN(Opportunity.CloseDate) FirstCloseDate, 
		    	MAX(Opportunity.CloseDate) LastCloseDate, COUNT_DISTINCT(Opportunity.Id) NumberOfClosedOpps
		    	FROM OpportunityContactRole 
		    	WHERE isPrimary=true AND opportunity.isWon=true 
		    	AND (Opportunity.Amount > 0 OR Opportunity.Amount < 0) 
		    	AND Opportunity.RecordTypeId NOT IN : recordTypesToExcludeCons
		    	AND Opportunity.Type NOT IN : oppTypesToExcludeCons
				AND (opportunity.accountid = : defaultAccountId OR opportunity.accountid = null)  
		    	AND contact.ONEN_household__c IN : hhIds
				GROUP BY CUBE(contact.ONEN_household__c, contactId, Calendar_Year(opportunity.closeDate))
				HAVING (Calendar_Year(opportunity.closeDate) = null 
    			OR Calendar_Year(opportunity.closeDate) >= : startYear ) 
    			AND contact.ONEN_household__c != null AND (contactId IN : conIds OR contactId = null) ] ) {
			
			//system.debug('ROLLUP ROW: ' + r);

			// get the ids
			id cid = (id)(r.get('contactId'));
			id hhid = (id)(r.get('hhid'));
				
			// process the result row, copying it into the contact record(s)
			if (cid == null) { 
				if (hhid != null)
					updateRollupFromResult((sobject)(householdsToUpdate.get(hhid)), r);
			} else {
				// contact row	
				updateRollupFromResult((sobject)(contactsToUpdate.get(cid)), r);
			}
		}
			
		// also do rollups for last N days
		for (sobject r : 
			[SELECT contact.ONEN_household__c hhid, contactId, 
		    	SUM(Opportunity.Amount) TotalOppAmount, COUNT_DISTINCT(Opportunity.Id) NumberOfClosedOpps
		    	FROM OpportunityContactRole 
		    	WHERE isPrimary=true AND opportunity.isWon=true 
		    	AND (Opportunity.Amount > 0 OR Opportunity.Amount < 0) 
		    	AND Opportunity.RecordTypeId NOT IN : recordTypesToExcludeCons
		    	AND Opportunity.Type NOT IN : oppTypesToExcludeCons
				AND (opportunity.accountid = : defaultAccountId OR opportunity.accountid = null)  
		    	AND contact.ONEN_household__c IN : hhIds
		    	AND opportunity.closeDate >= LAST_N_DAYS:365
				GROUP BY ROLLUP(contact.ONEN_household__c, contactId)
				HAVING contact.ONEN_household__c != null AND (contactId IN : conIds OR contactId = null) ] ) {

			//system.debug('ROLLUP ROW: ' + r);
			
			// get the ids
			id cid = (id)(r.get('contactId'));
			id hhid = (id)(r.get('hhid'));
				
			// process the result row, copying it into the contact record(s)
			if (cid == null) { 
				if (hhid != null)
					updateRollupFromResultLastNDays((sobject)(householdsToUpdate.get(hhid)), r);
			} else {
				// contact row	
				updateRollupFromResultLastNDays((sobject)(contactsToUpdate.get(cid)), r);
			}
		}

		// remove any records that have not changed
		for (id cid : conIds) {
			contact c1 = cmap.get(cid);
			contact c2 = contactsToUpdate.get(cid);
			if (c1.TotalOppAmount__c == c2.TotalOppAmount__c && 
					c1.OppAmountLastNDays__c == c2.OppAmountLastNDays__c &&
					c1.OppAmountThisYear__c == c2.OppAmountThisYear__c &&
					c1.LastCloseDate__c == c2.LastCloseDate__c)
				contactsToUpdate.remove(cid);
		}
		for (id hhid : hhIds) {
			ONEN_household__c hh1 = hhmap.get(hhid);
			ONEN_household__c hh2 = householdsToUpdate.get(hhid);
			if (hh1.TotalOppAmount__c == hh2.TotalOppAmount__c && 
					hh1.OppAmountLastNDays__c == hh2.OppAmountLastNDays__c &&
					hh1.OppAmountThisYear__c == hh2.OppAmountThisYear__c &&
					hh1.LastCloseDate__c == hh2.LastCloseDate__c)
				householdsToUpdate.remove(hhid);
		}

		// update all the contacts from this batch 
		if (!contactsToUpdate.isEmpty()) update contactsToUpdate.values();				
		if (!householdsToUpdate.isEmpty()) update householdsToUpdate.values();				
	}

	public void rollupForOppTrigger( map<id, opportunity> newOpps, map<id, opportunity> oldOpps ) {
	// find contacts and accounts affected and then roll them up

		if (triggerRollupEnabled) {

			set<id> modifiedContactOpps = new set<id>();
			set<id> acctsToReroll = new set<id>(); 

			if (newOpps == null) {
	
				// it is a delete
				for (id oid : oldOpps.keySet()) {
					opportunity o = oldOpps.get(oid);
					if (o.isWon && (o.Amount > 0 || o.Amount < 0)) {
						
						if ((o.accountid == defaultAccountId || o.accountid == null) &&
							(!recordTypesToExcludeCons.contains(o.recordTypeId)) &&
							(!oppTypesToExcludeCons.contains(o.type))) {
						
							modifiedContactOpps.add(o.id);
						}
						if (o.accountId != null &&
							(!recordTypesToExcludeAccts.contains(o.recordTypeId)) &&
							(!oppTypesToExcludeAccts.contains(o.type))) {
								
							acctsToReroll.add(o.accountId);
						}
					}
				}
			} else if (oldOpps == null) {
				// for insert, find the closed opps that qualify
				for (id oid : (newOpps.keySet())) {
					opportunity o = newOpps.get(oid);
					if (o.isWon && (o.Amount > 0 || o.Amount < 0)) {
						
						if ((o.accountid == defaultAccountId || o.accountid == null) &&
							(!recordTypesToExcludeCons.contains(o.recordTypeId)) &&
							(!oppTypesToExcludeCons.contains(o.type))) {
						 
							modifiedContactOpps.add(o.id);
						}
						if (o.accountId != null &&
							(!recordTypesToExcludeAccts.contains(o.recordTypeId)) &&
							(!oppTypesToExcludeAccts.contains(o.type))) {

							acctsToReroll.add(o.accountId);
						}
					}
				}
				
			} else {
				// for update, find the opps that are changed in any important way
				for (id oid : (newOpps.keySet())) {
					
					// compare old and new
					opportunity o = newOpps.get(oid);
					opportunity oldOpp = oldOpps.get(oid);

					// look for opps that have changed in any important way
					if (o.isWon != oldOpp.isWon || (o.isWon && 
						((o.Amount != oldOpp.Amount) ||
						(o.recordTypeId != oldOpp.recordTypeId) || 
						(o.type != oldOpp.type) ||
						(o.closeDate != oldOpp.closeDate) ||
						(o.accountId != oldOpp.accountId)))) { 
	
						if (o.accountid == defaultAccountId || o.accountid == null)
							modifiedContactOpps.add(o.id);
							
						if (o.accountId != null)
							acctsToReroll.add(o.accountId);
					}		
				}			
			}		
			
			// use the contact roles to find the contacts and households
			if (!modifiedContactOpps.isEmpty()) {
				map<id, contact> cmap = new map<id, contact>();
				map<id, onen_household__c> hhmap = new map<id, onen_household__c>();
				
				for (OpportunityContactRole r : 
					[SELECT contactId, contact.onen_household__c,
						contact.TotalOppAmount__c, contact.OppAmountThisYear__c, contact.OppAmountLastNDays__c, contact.LastCloseDate__c, contact.NumberOfClosedOpps__c,
						contact.onen_household__r.TotalOppAmount__c, contact.onen_household__r.OppAmountThisYear__c, contact.onen_household__r.OppAmountLastNDays__c, 
						contact.onen_household__r.LastCloseDate__c, contact.onen_household__r.NumberOfClosedOpps__c
				    	FROM OpportunityContactRole WHERE Opportunity.Id In : modifiedContactOpps and isPrimary = true ALL ROWS ] ) {		
					
					cmap.put(r.contactId, r.contact);
					hhmap.put(r.contact.onen_household__c, r.contact.onen_household__r);
				}
					
				if (!cmap.isEmpty()) {
					// for a single contact with fewer than 200 opps, roll up immediately - otherwise future
					decimal oppCount = cmap.values()[0].onen_household__r.NumberOfClosedOpps__c;
					if (cmap.size() == 1 && (oppCount == null || oppCount < 200))
						rollupContacts( cmap, hhmap );
					else if ((Limits.getLimitFutureCalls() - Limits.getFutureCalls()) > 5)
						rollupHouseholdsFuture(hhmap.keySet());
					else
						system.debug('Did not roll up because there were too few future calls available.');
				}
			}
	
			// roll them up
			if (!acctsToReroll.isEmpty()) {
				
				boolean rollupNow = false;
				map<id, account> amap;
				if (acctsToReroll.size() == 1) {
					amap = new map<id, account>(
						[select id, TotalOppAmount__c, OppAmountThisYear__c, OppAmountLastNDays__c, 
						LastCloseDate__c, NumberOfClosedOpps__c  
						from account where id in :acctsToReroll ]);
					decimal oppCount = amap.values()[0].NumberOfClosedOpps__c;
					rollupNow = (oppCount == null || oppCount < 200);
				}
						
				// for a single account with fewer than 200 opps, roll up immediately - otherwise future
				if (rollupNow)
					rollupAccounts( amap );
				else if ((Limits.getLimitFutureCalls() - Limits.getFutureCalls()) > 5)
					rollupAccountsFuture( acctsToReroll );
				else
					system.debug('Did not roll up because there were too few future calls available.');				
			}
		}	
	}

	public void rollupAll() {
		rollupAllAccounts();
		rollupAllContacts();
	}	

	public void rollupAllAccounts() {

		// we can handle up to 10000 query rows total, which is about 3000 opps in a batch
		// this calculation very conservatively reduces batch size to avoid hitting the limit
		integer batchSize = 200;
		list<account> topAccount = [select NumberOfClosedOpps__c from account 
			where NumberOfClosedOpps__c != null 
			order by NumberOfClosedOpps__c desc limit 1];
		if (!topAccount.isEmpty()) {
			decimal highestCount = topAccount[0].NumberOfClosedOpps__c;
			if (highestCount > 15) {
				batchSize = (3000 / highestCount).intValue() + 1;
			}
		}

		// start the batch to roll up all accounts
		GW_BATCH_OppRollup batch = new GW_BATCH_OppRollup( 'SELECT id, TotalOppAmount__c, OppAmountThisYear__c, ' +
			'OppAmountLastNDays__c, LastCloseDate__c, NumberOfClosedOpps__c FROM account' + 
			(isTest ? ' WHERE name like \'%test%\' LIMIT 200' : '') );
		id batchProcessId = database.executeBatch(batch, batchSize);		
	}	
		
	public void rollupAllContacts() {

		// we can handle up to 10000 query rows total, which is about 3000 opps in a batch
		// this calculation very conservatively reduces batch size to avoid hitting the limit
		integer batchSize = 200;
		list<onen_household__c> topHousehold = [select NumberOfClosedOpps__c from onen_household__c 
			where NumberOfClosedOpps__c != null 
			order by NumberOfClosedOpps__c desc limit 1];
		if (!topHousehold.isEmpty()) {
			decimal highestCount = topHousehold[0].NumberOfClosedOpps__c;
			if (highestCount > 15) {
				batchSize = (3000 / highestCount).intValue() + 1;
			}
		}

		GW_BATCH_OppRollup batch = new GW_BATCH_OppRollup( 'SELECT id, TotalOppAmount__c, OppAmountThisYear__c, ' +
			'OppAmountLastNDays__c, LastCloseDate__c, NumberOfClosedOpps__c FROM onen_household__c' + 
			(isTest ? ' WHERE lastname like \'%doppleganger%\' LIMIT 200' : '') );
		id batchProcessId = database.executeBatch(batch, batchSize);		
	}

	public static void updateRollupFromResult(sobject obj, sobject r) {
	// used for single and batch rollups, this maps query results to the right fields
		
		// get the fiscal year, total amount, and opp count for this result row		
		integer fy = (integer)(r.get('CalendarYr'));
		decimal amt = (decimal)(r.get('TotalOppAmount'));
		integer cnt = (integer)(r.get('NumberOfClosedOpps'));				
		
		// check if this is an annual total or account total
		if (fy != null) {

			// put the fiscal year total in the right fields
			integer thisYear = system.today().year();
			if (fy == thisYear) {
				obj.put('OppAmountThisYear__c', amt); 
				obj.put('OppsClosedThisYear__c', cnt); 
			} else if (fy == (thisYear - 1)) {
				obj.put('OppAmountLastYear__c', amt); 
				obj.put('OppsClosedLastYear__c', cnt); 
			} else if (fy == (thisYear - 2) ) {
				obj.put('OppAmount2YearsAgo__c', amt); 
				obj.put('OppsClosed2YearsAgo__c', cnt); 
			} 
				
		} else {

			// fill in summary totals
			obj.put('TotalOppAmount__c', amt);
	        obj.put('NumberOfClosedOpps__c', cnt); 				
	        obj.put('AverageAmount__c', (decimal)(r.get('AverageAmount'))); 
	        obj.put('SmallestAmount__c', (decimal)(r.get('SmallestAmount'))); 
	        obj.put('LargestAmount__c', (decimal)(r.get('LargestAmount'))); 
	        obj.put('FirstCloseDate__c', (date)(r.get('FirstCloseDate'))); 
	        obj.put('LastCloseDate__c', (date)(r.get('LastCloseDate'))); 
		}
	}

	public static void updateRollupFromResultLastNDays(sobject obj, sobject r) {
	// used for single and batch rollups, this maps query results to the right fields
		
		// get the fiscal year, total amount, and opp count for this result row		
		decimal amt = (decimal)(r.get('TotalOppAmount'));
		integer cnt = (integer)(r.get('NumberOfClosedOpps'));				
		
		// fill in totals
        obj.put('OppAmountLastNDays__c', amt); 				
		obj.put('OppsClosedLastNDays__c', cnt);
	}

	/************ TESTS ***************/
	
	static testMethod void testGivingRollup () {
		
		Date datClose = System.Today();
			
		// create & insert contact(s)
		Contact[] TestCons = new contact[]{ new contact(firstname='Daddy', lastname='Longlegs') };
		insert TestCons;

		// create new opps
		Opportunity[] newOpps = ONEN_UnitTestData.OppsForContactList ( TestCons, null, 'Closed Won', datClose, 100 , ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS ,null);

		// insert the opp(s)
		isTest = true;
		Test.StartTest();
		insert newOpps;
		
		//now test that a contact has received the proper member stats from the trigger
		id FirstConId = TestCons[0].id;
		Contact UpdatedCon = [SELECT id, account.TotalOppAmount__c, OppAmountThisYear__c, OppAmountLastYear__c, onen_household__c, onen_household__r.TotalOppAmount__c, TotalOppAmount__c FROM Contact WHERE Id = :FirstConId];

		System.AssertEquals ( 100 , UpdatedCon.TotalOppAmount__c );
		System.AssertEquals ( 100 , UpdatedCon.onen_household__r.TotalOppAmount__c );		
		System.AssertEquals ( 100 , UpdatedCon.OppAmountThisYear__c);
		System.AssertEquals ( 0 , UpdatedCon.OppAmountLastYear__c);

		// now roll up manually
		GW_OppRollups rg = new GW_OppRollups();
		rg.rollupContact(testcons[0].id);

		//make sure the values are still right
		UpdatedCon = [SELECT id, account.TotalOppAmount__c, OppAmountThisYear__c, OppAmountLastYear__c, onen_household__c, onen_household__r.TotalOppAmount__c, TotalOppAmount__c FROM Contact WHERE Id = :FirstConId];

		System.AssertEquals ( 100 , UpdatedCon.TotalOppAmount__c );
		System.AssertEquals ( 100 , UpdatedCon.onen_household__r.TotalOppAmount__c );		
		System.AssertEquals ( 100 , UpdatedCon.OppAmountThisYear__c);
		System.AssertEquals ( 0 , UpdatedCon.OppAmountLastYear__c);
		
		// also try the future call, which only gets used if the trigger fails
		GW_OppRollups.rollupHouseholdsFuture( new set<id> { updatedCon.onen_household__c } );
		Test.StopTest();
		
		//make sure the values are still right
		UpdatedCon = [SELECT id, account.TotalOppAmount__c, OppAmountThisYear__c, OppAmountLastYear__c, onen_household__c, onen_household__r.TotalOppAmount__c, TotalOppAmount__c FROM Contact WHERE Id = :FirstConId];

		System.AssertEquals ( 100 , UpdatedCon.TotalOppAmount__c );
		System.AssertEquals ( 100 , UpdatedCon.onen_household__r.TotalOppAmount__c );		
		System.AssertEquals ( 100 , UpdatedCon.OppAmountThisYear__c);
		System.AssertEquals ( 0 , UpdatedCon.OppAmountLastYear__c);
	}
	
	static testMethod void testGivingRollupAcct () {

		Date datClose = System.Today();

		// create account
		account testacct = new account(name='testacct');
		insert testacct;
		opportunity newOpp =
			 new opportunity (name = 'testopp', accountid = testacct.id, 
			 					stagename='Closed Won', closedate=datClose, amount=33333);
		
		// insert the opp(s)
		Test.StartTest();
		isTest = true;
		insert newOpp;

		// test whether the trigger worked		
		account updatedAcct = [select id, totalOppAmount__c from account where id =: testacct.id];		
		System.AssertEquals ( 33333 , updatedAcct.TotalOppAmount__c );		

		// now roll up manually
		GW_OppRollups rg = new GW_OppRollups();
		rg.rollupAccount(testacct.id);

		updatedAcct = [select id, totalOppAmount__c from account where id =: testacct.id];
		System.AssertEquals ( 33333 , updatedAcct.TotalOppAmount__c );		

		// also try the future call, which only gets used if the trigger fails
		GW_OppRollups.rollupAccountsFuture( new set<id> { testacct.id } );

		Test.StopTest();

		updatedAcct = [select id, totalOppAmount__c from account where id =: testacct.id];
		System.AssertEquals ( 33333 , updatedAcct.TotalOppAmount__c );		
	
	}	

	static testMethod void testGivingRollupBatch () {
		
		Date datClose = System.Today();
			
		// create & insert contact(s)
		Contact[] TestCons = ONEN_UnitTestData.CreateMultipleTestContacts ( 100 ) ;
		insert TestCons;

		// create new opps
		Opportunity[] newOpps = ONEN_UnitTestData.OppsForContactList ( TestCons, null, 'Closed Won', datClose, 1000 , ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS ,null);

		account testacct = new account(name='testacct');
		insert testacct;

		// test the batch rollup method
		isTest = true; 
		Test.StartTest();
		GW_OppRollups rg = new GW_OppRollups();
		rg.rollupAll();
		Test.StopTest();
	}	

	static testMethod void OneContactMultipleOpps() {

		integer howMany = 1;
		Date datToday = System.Today();
		Date dat1YearAgo = Date.newInstance( datToday.year()-1,1,1);
		Date dat2YearAgo = Date.newInstance( datToday.year()-2,1,1);
		Date dat4YearAgo = Date.newInstance( datToday.year()-4,1,1);
			
		// create & insert contact(s)
		Contact[] TestCons = ONEN_UnitTestData.CreateMultipleTestContacts ( howMany ) ;
		insert TestCons;
		
		test.starttest();
		isTest = true;
		system.debug ( 'TEST>>>>> inserting gift 1...');
		
		// create a new gift for this yr
		Opportunity[] testGift1 = ONEN_UnitTestData.OppsForContactList ( TestCons, null, 'Closed Won', datToday, 100 , ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS,null);
		insert testGift1 ;
		
		// reset the conrole creation flag so we'll get conroles for this 2nd insert
		ONEN_OpportunityContactRoles.haveCheckedContactRoles = false;

		system.debug ( 'TEST>>>>> inserting gift 2...');
		
		//create a 2nd gift for last yr
		Opportunity[] testGift2 = ONEN_UnitTestData.OppsForContactList ( TestCons, null, 'Closed Won', dat1YearAgo, 60, ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS,null);
		ONEN_OpportunityContactRoles.haveCheckedContactRoles = false;
		insert testGift2;
		
		//test.stopTest();
		
		//now test that the contact has received the proper stats from the trigger
		id ThisConId = TestCons[0].id;
		Contact UpdatedCon = [SELECT Id,  totalOppAmount__c, OppAmountThisYear__c, OppAmountLastYear__c FROM Contact WHERE Id = :ThisConId];
		
		System.AssertEquals ( 160 , UpdatedCon.totalOppAmount__c );
		System.AssertEquals ( 100 , UpdatedCon.OppAmountThisYear__c );
		System.AssertEquals ( 60 , UpdatedCon.OppAmountLastYear__c );


		system.debug ( 'TEST>>>>> changing gift 1...');
		
		// now chg the amts for both opps (cheapskate!)
		testGift1[0].Amount = 50;
		update TestGift1;

		system.debug ( 'TEST>>>>> changing gift 2...');
		
		testGift2[0].Amount=25;
		update TestGift2;
		
		//now test that the contact has updated stats from the trigger
		ThisConId = TestCons[0].id;
		UpdatedCon = [SELECT Id, totalOppAmount__c, OppAmountThisYear__c, OppAmountLastYear__c  FROM Contact WHERE Id = :ThisConId];
		
		System.AssertEquals ( 75 , UpdatedCon.totalOppAmount__c );
		System.AssertEquals ( 50 , UpdatedCon.OppAmountThisYear__c );		
		System.AssertEquals ( 25 , UpdatedCon.OppAmountLastYear__c );
		

		system.debug ( 'TEST>>>>> inserting gift 3...');

		// now create a gift from 2 yrs ago
		Opportunity[] testGift3 = ONEN_UnitTestData.OppsForContactList ( TestCons, null, 'Closed Won', dat2YearAgo, 10 , ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS,null);
		ONEN_OpportunityContactRoles.haveCheckedContactRoles = false;
		insert testGift3;

		//now test that the contact has updated stats from the trigger
		ThisConId = TestCons[0].id;
		UpdatedCon = [SELECT Id,  totalOppAmount__c, OppAmountThisYear__c, OppAmountLastYear__c, OppAmount2YearsAgo__c FROM Contact WHERE Id = :ThisConId];
		
		System.AssertEquals ( 85 , UpdatedCon.totalOppAmount__c );
		System.AssertEquals ( 50 , UpdatedCon.OppAmountThisYear__c );		
		System.AssertEquals ( 25 , UpdatedCon.OppAmountLastYear__c );
		System.AssertEquals ( 10 , UpdatedCon.OppAmount2YearsAgo__c );

		// add another from this year (to test adding)
		system.debug ( 'TEST>>>>> inserting gift 4...');
		Opportunity[] testGift4 = ONEN_UnitTestData.OppsForContactList ( TestCons, null, 'Closed Won', datToday, 25 , ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS,null);
		ONEN_OpportunityContactRoles.haveCheckedContactRoles = false;
		insert testGift4;

		UpdatedCon = [SELECT Id,  totalOppAmount__c, OppAmountThisYear__c, OppAmountLastYear__c, OppAmount2YearsAgo__c FROM Contact WHERE Id = :ThisConId];
		
		System.AssertEquals ( 110 , UpdatedCon.totalOppAmount__c );
		System.AssertEquals ( 75 , UpdatedCon.OppAmountThisYear__c );		
		System.AssertEquals ( 25 , UpdatedCon.OppAmountLastYear__c );
		System.AssertEquals ( 10 , UpdatedCon.OppAmount2YearsAgo__c );

		// TBD add a gift from longer ago
		system.debug ( 'TEST>>>>> inserting gift 5...');
		Opportunity[] testGift5 = ONEN_UnitTestData.OppsForContactList ( TestCons, null, 'Closed Won', dat4YearAgo, 200 , ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS,null);
		ONEN_OpportunityContactRoles.haveCheckedContactRoles = false;
		insert testGift5;
		
		// totals should not have changed, except lifetime
		UpdatedCon = [SELECT Id,  totalOppAmount__c, OppAmountThisYear__c, OppAmountLastYear__c, OppAmount2YearsAgo__c FROM Contact WHERE Id = :ThisConId];
		
		System.AssertEquals ( 310 , UpdatedCon.totalOppAmount__c );
		System.AssertEquals ( 75 , UpdatedCon.OppAmountThisYear__c );		
		System.AssertEquals ( 25 , UpdatedCon.OppAmountLastYear__c );
		System.AssertEquals ( 10 , UpdatedCon.OppAmount2YearsAgo__c );		
		
		// TBD add non-won gift
		system.debug ( 'TEST>>>>> inserting gift 6...');
		Opportunity[] testGift6 = ONEN_UnitTestData.OppsForContactList ( TestCons, null, 'Prospecting', dat4YearAgo, 35 , ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS,null);
		ONEN_OpportunityContactRoles.haveCheckedContactRoles = false;
		insert testGift6;
		
		// totals should not have changed at all
		UpdatedCon = [SELECT Id,  totalOppAmount__c, OppAmountThisYear__c, OppAmountLastYear__c, OppAmount2YearsAgo__c FROM Contact WHERE Id = :ThisConId];
		
		System.AssertEquals ( 310 , UpdatedCon.totalOppAmount__c );
		System.AssertEquals ( 75 , UpdatedCon.OppAmountThisYear__c );		
		System.AssertEquals ( 25 , UpdatedCon.OppAmountLastYear__c );
		System.AssertEquals ( 10 , UpdatedCon.OppAmount2YearsAgo__c );		
				
		// now delete the 1st gift (now at $50), totals should decrease
		system.debug ( 'TEST>>>>> deleting gift 1...');	
		delete testGift1;
		
		UpdatedCon = [SELECT Id,  totalOppAmount__c, OppAmountThisYear__c, OppAmountLastYear__c, OppAmount2YearsAgo__c FROM Contact WHERE Id = :ThisConId];
		
		System.AssertEquals ( 260 , UpdatedCon.totalOppAmount__c );
		System.AssertEquals ( 25 , UpdatedCon.OppAmountThisYear__c );		
		System.AssertEquals ( 25 , UpdatedCon.OppAmountLastYear__c );
		System.AssertEquals ( 10 , UpdatedCon.OppAmount2YearsAgo__c );		
		
		
	}

	static testMethod void OneContactOneInkind() {
		
		integer howMany = 1;
		Date datToday = System.Today();
		
		// create & insert contact(s)
		Contact[] TestCons = ONEN_UnitTestData.CreateMultipleTestContacts ( howMany ) ;
		insert TestCons;
		
		system.debug ( 'TEST>>>>> inserting gift 1...');
		
		// create a new gift for this yr
		Opportunity[] testGift1 = ONEN_UnitTestData.OppsForContactList ( TestCons, null, 'Closed Won', datToday, 100 , ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS,'In-Kind');
		isTest = true;
		insert testGift1 ;
		
		id ThisConId = TestCons[0].id;
		contact UpdatedCon = [SELECT Id,  totalOppAmount__c, OppAmountThisYear__c, OppAmountLastYear__c, OppAmount2YearsAgo__c FROM Contact WHERE Id = :ThisConId];
	
		System.AssertEquals ( null , UpdatedCon.totalOppAmount__c );
		
		testGift1[0].Type = 'Cash';
		update testGift1;
		
		UpdatedCon = [SELECT Id,  totalOppAmount__c, OppAmountThisYear__c, OppAmountLastYear__c, OppAmount2YearsAgo__c FROM Contact WHERE Id = :ThisConId];
		System.AssertEquals ( 100 , UpdatedCon.totalOppAmount__c );
		
	
	}

	static testMethod void testGivingRollupBulk () {
	
		// for a single contact w/ no previous mbrships, add a new membership
		// and test mbr stats are created
		integer howMany = 50;
		Date datClose = System.Today();
			
		// create & insert contact(s)
		Contact[] TestCons = ONEN_UnitTestData.CreateMultipleTestContacts ( howMany ) ;
		insert TestCons;
		
		// create new opps
		Opportunity[] newOpps1 = ONEN_UnitTestData.OppsForContactList ( TestCons, null, 'Closed Won', datClose, 100 , ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS,null);
		Opportunity[] newOpps2 = ONEN_UnitTestData.OppsForContactList ( TestCons, null, 'Closed Won', datClose.addYears(-1), 50 , ONEN_Constants.OPP_DEFAULT_RECTYPE_FORTESTS,null);

		// insert the opp(s)
		Test.StartTest();
		isTest = true;
		insert newOpps1;

		// reset the conrole creation flag so we'll get conroles for this 2nd insert
		ONEN_OpportunityContactRoles.haveCheckedContactRoles = false;
		insert newOpps2;

		Test.StopTest();
		
		id FirstConId = TestCons[10].id;
		Contact UpdatedCon = [SELECT Id,  totalOppAmount__c, OppAmountThisYear__c, OppAmountLastYear__c, OppAmount2YearsAgo__c FROM Contact WHERE Id = :FirstConId];
		
		System.AssertEquals ( 150 , UpdatedCon.totalOppAmount__c );
		System.AssertEquals ( 100 , UpdatedCon.OppAmountThisYear__c );		
		System.AssertEquals ( 50 , UpdatedCon.OppAmountLastYear__c );
		System.AssertEquals ( 0 , UpdatedCon.OppAmount2YearsAgo__c );
		
	}

	static testMethod void testGivingRollupTooManyOpps () {
	
		// for a single contact w/ no previous mbrships, add a new membership
		// and test mbr stats are created
	
		// create & insert contact(s)
		Contact[] TestCons = ONEN_UnitTestData.CreateMultipleTestContacts ( 1 ) ;
		insert TestCons;
		
		// create new opps
		Opportunity[] newOpps1 = new Opportunity[0];
		for (integer n = 0; n < 450; n++) {
			newOpps1.add( new opportunity( cr_contact_id__c = TestCons[0].id, name = 'test opp ' + n, 
				stagename = 'Closed Won', closedate = system.today().adddays(-n), amount = 100));
		}
		
		// insert the opp(s)
		Test.StartTest();
		isTest = true;
		insert newOpps1;
		Test.StopTest();
		
		id FirstConId = TestCons[0].id;
		Contact UpdatedCon = [SELECT Id,  totalOppAmount__c, OppAmountThisYear__c, OppAmountLastYear__c, OppAmount2YearsAgo__c FROM Contact WHERE Id = :FirstConId];
		
		System.AssertEquals ( 45000 , UpdatedCon.totalOppAmount__c );
		
	}
}