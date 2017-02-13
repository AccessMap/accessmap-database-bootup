# Issues

### Under/overpasses mess up offset sidewalks

Example: University Bridge going to Eastlake. Underpass sidewalks get split
where the bridge is due to the way the algorithm currently works (takes every
nearby street, makes a buffer, substracts it).

Potential solutions:

* Use SNDSEG STRUCTURE_TYPE in original dataset, indicates vertical position.
OSM will have similar data, so good to plan for it now.

* Write new algo that doesn't use buffers (e.g. right hand offsets algorithm).

### Highways/raised train tracks etc mess up offset sidewalks

Example: I-5 can split path, as can monorail tracks.

Potential solutions:

* Use street categories + elevation info to make decisions. Street-ish
categories are listed in SNDSEG_FEACODE, over/underpasses STRUCTURE_TYPE.
SEGMENT_TYPE is even more specific, could be handy (onramps, etc).

### Pedestrian streets are considered barriers

Example: none yet, but I'm sure they're out there

Potential solutions:

* Use the VEHICLE_USE_CODE flag.

### Some sidewalks get cut off mid-block for no apparent reason

Example: Westlake station area - sidewalks on 3rd get cut off and so do
sidewalks on pine.

Potential solutions:

* Needs more research to figure out why this is happening. One possible
cause could be the street buffer created by streets that do *not* have
sidewalks, as I think is the case for the second segment on third.

* These are both proximal to geometries in the street network dataset that
are actually footpaths (feacode 77) in Westlake Plaza. Aggressively filtering
the streets treated as sidewalk barriers may solve this problem.

### Eastlake bridge area produces a *giant* buffer

Potential solutions:

* Needs research first
