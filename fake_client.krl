ruleset fake_client {
  meta {
    shares __testing
    use module io.picolabs.subscription alias Subscriptions
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
      store_eci = Subscriptions:established("Tx_role", "store")[0]{"Tx"}
    }
    
    if bid then
      event:send({"eci": store_eci, 
                  "domain":"store", "type":"accepted_bid", 
                  "attrs":{"bid": bid}});
  }
}
