Distributed Fast Flower Delivery Report
Connor Wilhelm
Daniel Brown
Charlie Oliverson
 
## Statement of the problem you were solving
We are solving the Fast Flower Delivery problem using a decentralized, distributed system. The Fast Flower Delivery problem is to create a system where flower stores can communicate with independent delivery drivers. When the store gets an order, it sends a delivery request to drivers. The drivers return bids, and the store can accept one bid per delivery. The customer is notified of the delivery. The driver performs the delivery. Drivers have profiles that rank their effectiveness. In addition to this problem, we need to ensure that our solution is decentralized and heterarchical.
## List of component APIs and why you chose them
The two APIs we used were Twilio and Google Maps Distance Matrix. Twilio allows the store to communicate with the customer through SMS. We decided to use SMS communication because we didn’t want to assume the customer owned a node in the delivery system. The customer doesn’t even need to be aware of our system to benefit from it. The Google API allows drivers to calculate their distance from a delivery’s destination, so they can decide if they are in range. This allows them to consider the distance of requests in making their price bid, and whether they want to bid at all. We chose this API because it is easy to use and provides distance information without irrelevant information.
## Description of the actors (event generators and consumers)
Our two main actors are flower stores and drivers. Stores initiate the exchange by sending requests to the drivers they know. They accept a driver’s bid and communicate with the driver as they perform the delivery. They also communicate with the customer through SMS.

Drivers act in two different roles: drivers and gossipers. As drivers, they create bids for delivery requests from stores. When a store notifies a driver that they have accepted a bid, the driver and store communicate directly.

As gossipers, drivers propagate the bid requests to other drivers. They use the gossip protocol to send bids as gossip to all drivers they are connected to. This allows drivers to communicate in a heterarchical way, as each driver acts as an equal gossiper. We assume that all drivers propagate all bids they receive; in other words, there are no malicious driver nodes. While we could have used an intermediary as gossipers, we decided against it, as they would need incentive to do so. Since drivers have incentive to gossip (perhaps an agreement to allow for fair competition), they were a natural choice for gossipers.

## Description of the API (i.e. events and queries)
Store Receives
  ```Store:new_order
  Store:order_delivered
  Store:new_bid
  Store:update_profile
  Store:accepted_bid 
```
Store Sends
```  Driver:delivery_request
  Driver:assigned_delivery
  Client:bids_available
```
Driver Receives
```  Driver:delivery_request
  Driver:assigned_delivery
  Gossip:rumor
  Gossip:seen
```
Driver Sends
  ```
  Store:new_bid
  Store:order_delivered
  Gossip:rumor
  Gosip:seen
  ```
## Architectural diagram and explanation
    
A store sends a delivery request to all the drivers that it knows about. The drivers then propagate the delivery request to all other drivers via gossip protocol. Each driver then uses the Google Distance Matrix API to determine whether or not it is close enough to the delivery destination to make the delivery on time. If and only if it is close enough does a driver send a driving bid back to the store. The store then weighs all of the bids and determines which one will deliver the order. The store then communicates with only that driver, informing them that it has won the bid and will deliver the flower order. At the same time, a SMS is sent via the Twilio API to the customer, informing them that the order has been scheduled for delivery. Once the driver has delivered the order, a notification is sent back to the store, informing them that the delivery has been completed.

In the diagram, the different requests have been color coded.
  ```Purple: Entities 
  Red: delivery request from the store
  Light Blue: Interactions with 3rd party APIs
  Green: Driver bids and whether or not they were sent
  Brown: The store’s selection of a bid and associated communications
  Orange: Notification from the driver that the flowers have been delivered
  ```      

## Analysis of why events were or were not a good solution to the problem you chose. Give pros and cons. 
### Pros:
* An actor can respond to one event in multiple ways. For example, upon receiving a driver delivery_request event, drivers process requests they receive to create a bid and propagate requests as gossip.
* Each actor processes events asynchronously
* Picos use non-blocking I/O, so one event doesn’t stop it from receiving others
* Events decouple actors
* Events can easily be sent over HTTP since picos are first-class internet citizens.
### Cons
* Following the trail of events is sometimes difficult, making debugging and making changes difficult

Code can be found at our public GitHub Repository: https://github.com/derbraun/CS462_Final

