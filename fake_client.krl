ruleset fake_client {
  meta {
    shares __testing
  }
  global {
    __testing = { "queries":
      [ { "name": "__testing" }
      //, { "name": "entry", "args": [ "key" ] }
      ] , "events":
      [ //{ "domain": "d1", "type": "t1" }
      //, { "domain": "d2", "type": "t2", "attrs": [ "a1", "a2" ] }
      ]
    }
    
    getRandomBid = function(order){
      bids = order{"bids"};
      bids.length() > 0 => 
        bids[random:integer(bids.length()-1)]
        | null;
    }
    
  }
  
  rule bids_available {
    select when client bids_available
    
    pre {
      bid = getRandomBid(event:attrs{"order"}).klog("BIDS");
    }
    
    if bid then
      event:send({"eci": "E5msNJU1TkDswBvpNWpqQD", 
                  "domain":"store", "type":"accepted_bid", 
                  "attrs":{"bid": bid}});
  }
}
