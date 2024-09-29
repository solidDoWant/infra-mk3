# Brocade ICX custom rear rack mount ears

This is a custom, adjustable-length rack mount solution for Brocade ICX 7250 switches. It probably works for most Brocade ICX 7xxx switches, but has not been tested with them. This is intended as a replacement for Brocade part number XBR-R000295 and XBR-R000296, which are hard to find and extremely expensive for a couple of metal plates.

## Manufacturing information

Note: These are designed to fit a ICX 7250 in a 27.5" to 36" deep racks. If your rack is outside of this range, these probably won't fit. This can by increasing BOTH the rear ear slot length, and the length of the extension plate.

These are designed to be produced by [SendCutSend](https://sendcutsend.com). [fabworks](https://fabworks.com) should also work as well. The pieces are configured as follows:

### Common configuration
* 1.88mm/0.074" 1008 steel.
* Any finish (buyer's preference). Note that SendCutSend will not debur these parts unless you get them powder coated, but fabworks will.

### Extension plate
* The back four screw holes need 8-32 nut hardware inserts added.

### Rear ears
* A 90 degree bend must be added near the actual ear.

### Lacing bar (optional)
* Two 90 degree bends must be added at each end.
* The four holes need 8-32 nut hardware inserts added.

## Assembly steps

Assembly is pretty simple. Here's how to mount a switch with these ears, **as well as the out of the box front side ears**. I don't currently have a model for these, but they should be pretty easy to draw if somebody needs them.

1. Attach the front side ears with the provided four 6-32 x 5/16" screws on each side.
2. Attach the extension plates to the rear of the switch. Use four more 8-32 x 5/16" screws (per side), but with round heads. Most hardware stores should have these. If you want to order everything online, [these should work](https://www.amazon.com/Machine-Finish-B18-6-3-Phillips-Threaded/dp/B00F34YYEG). The nut inserts should be on the outside.
3. Mount the switch/plate assembly in your rack using normal cage nuts/bolts.
4. Mount the rear ears in your rack using normal cage nuts and bolts. These should mate to the INSIDE of the extender plate, not the side with the nuts.
5. Use four more 8-32 x 5/16" screws (per side) to attach the switch/plate assembly assembly to the rear ears.

## Complete parts list for mounting one switch
* 1x ICX 7250
* 2x Brocade-provided front side ears
* 8x Brocade-provided 6-32 x 5/16" screws for front side ears (flat head for countersink)
* 2x SendCutSend-manufactured extension plates
* 2x SendCutSend-manufactured rear ears
* 16x 8-32 x 5/16" screws with round heads
* 8x cage nuts
* 8x cage bolts
* 1x Phillips head screwdriver

Optional:
* 1 SendCutSend-manufactured lacing bar
* 8x 8-32 x 5/16" screws with round heads

The total cost of this (excluding Brocade-provided parts/switch), with powder coating on custom parts, is about $100. This will vary a bit based upon shipping and taxes. The cost can be roughly cut in half by not having the parts powder coated or otherwise finished.

TODO:
Figure out exact rack depth range
Switch nuts to 8-32 to make everything use the same hardware