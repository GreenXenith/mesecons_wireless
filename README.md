# Wireless Mesecons #
(includes Digiline support)

### Items ###
* Wireless Transmitter
* Wireless Receiver
* Antenna (craftitem)
* Radio Dish (craftitem)

### Crafting ###

#### Wireless Transmitter ####
![Imgur](https://i.imgur.com/H5tyvxE.png)  
Swap Digiline wire for Mesecon wire if Digilines is disabled

#### Antenna ####
![Imgur](https://i.imgur.com/Dz0mX5V.png)

#### Wireless Receiver ####
![Imgur](https://i.imgur.com/7i1G2Dg.png)  
Swap Digiline wire for Mesecon wire if Digilines is disabled

#### Radio Dish ####
![Imgur](https://i.imgur.com/fgylNAI.png)  
(Reversed direction is also acceptable)

### Usage ###
The `network` field in both the transmitter and receiver tell each node which channel to send and listen on, respectively. This is in no way related to Digiline channels.

The `range` field in the transmitter will set how far away a receiver can be to get a signal.

Up to 100 receivers can listen on one network. Multiple transmitters can send to the same network, however, behavior can be unexpected. This should really only be used in combination with luacontrollers.

Sending a Mesecon signal will result in a yellow signal indicator.
![Imgur](https://i.imgur.com/s40ZePy.png)

Sending a Digiline signal will result in a blue indicator (for a short time).
![Imgur](https://i.imgur.com/58ufKuI.png)
Transmitters and receivers are not digiline devices, they only carry the signal. They are similar to wires, except, wireless. Yes, Digiline and Mesecon signals can be sent in unison. Digiline signals will transmit regardless of the transmitter being active.

#### Overheating ####
Transmitters are limited to 20 signals per second. A Mesecon signal counts as 5, as they are much harder to send rapidly. When a transmitter overheats, the signal will appear red until it cools down a second later. No signals will transmit during this time.  
![Imgur](https://i.imgur.com/dccE0AR.png)
