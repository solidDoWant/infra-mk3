# Brocade ICX 7250 console cable

The switch uses a USB 2.0 type b mini female port as the serial console port (why???).

[![USB port types](https://upload.wikimedia.org/wikipedia/commons/8/82/USB_2.0_and_3.0_connectors.svg)](https://commons.wikimedia.org/wiki/File:USB_2.0_and_3.0_connectors.svg#/media/File:USB_2.0_and_3.0_connectors.svg)

A console cable can be purchased [for about $26 (at the time of writing)](https://www.amazon.com/Wirenest-Console-Brocade-ICX7250-Switches/dp/B0BF5Z5X8Z), or made from spare parts for little to no cost.

## Materials
* 1x USB type b mini cable (other end doesn't matter)
* 1x DB9 cable, or [breakout connector](https://www.amazon.com/gp/product/B09L7HLTWC/)

## Tools
* 1x wire stripper
* 1x soldering iron/solder/heat shrink/soldering tools (only needed if connections are made via splicing)

## Assembly steps

1. Cut the USB cable. Leave _at least_ a few inches of cable on the side with the USB type b mini connector. The other end can be discarded.
2. Cut back approximately half an inch of the outer cable jacket on the USB cable. Trim any shielding.
3. Strip the ground, D-, and D+ wires approximately 1/8" to 1/4". These are typically black, white, and green. Red is typically the Vcc wire, and should not be stripped to prevent an accidental short.
4. If using a DB9 cable, perform steps (1) through (3). The female side will be used, and the other side can be discarded. Instead of stripping the ground, D-, and D+ wires, [strip wires 5, 3, and 2](https://en.wikipedia.org/wiki/RS-232#Data_and_control_signals).
5. Make the following connections:
    * USB ground (usually black) to DB-9 wire ground (wire 5)
    * USB D- (usually white) to DB-9 wire TxD (wire 3)
    * USB D+ (usually green) to DB-9 wire RxD (wire 2)
6. Ensure that the connections are secure, and melt the heat shrink (if soldering) or close up the connector (if using a breakout connector).

The cable can now be plugged into a the switch, and a DB-9 RS-232 male port.