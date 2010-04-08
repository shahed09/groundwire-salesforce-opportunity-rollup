global class GW_SCHED_OppRollups implements Schedulable {
// run nightly for snappy opp totals
   
	global void execute(SchedulableContext SC) { 
		GW_OppRollups rg = new GW_OppRollups();
		rg.rollupAll();   
	}
	
}