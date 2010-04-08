trigger ONEN_Opportunity_GivingHistoryRollup on Opportunity (after insert, after update, after delete) {

	// check for the contact roles
	if ( Trigger.isInsert && ONEN_OpportunityContactRoles.haveCheckedContactRoles == false )
		ONEN_OpportunityContactRoles.CheckContactRoles ( trigger.newmap );  		
	
	// CALL THE NEW ROLLUP CODE
	GW_OppRollups rg = new GW_OppRollups(); 
	rg.rollupForOppTrigger(trigger.newMap, trigger.oldMap); 
	
}