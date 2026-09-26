class_name DemoGate
extends Node
## Demo builds only (M9 D6): Main adds one when BuildInfo.is_demo(). It owns
## the demo boundary (rooms outside the demo refuse to load and open the
## demo end card instead).
##
## stub: filled by T05.

## Dev: let the dev console walk past the demo boundary.
static var dev_bypass: bool = false
