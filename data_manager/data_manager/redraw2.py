def redraw_sidewalks(streets_path):
    # Strategy:
    # 1) Find rings in the streets dataset. Wanted to use
    #    shapely.ops.polygonize, but this loses the initial street data. Will
    #    instead roll my own clockwise LinearRing finder.
    # 2) Given the rings, create two ordered arrays of streets: one forward,
    #    one backward around the ring.
    # 3) Apply parallel offset algo to the rings.
    # 4) Trim back using 'next line' info. Draw line from beginning of next
    #    line to its first offset point if no endcap were used (i.e.
    #    intersection between orthogonal line from start point and offset).
    #    Cut the current sidewalk with that line and throw out all but the
    #    first segment.
    # 5) Look 'back' as well, and follow the same basic procedure.
    # 6) If connecting streets have right-hand sidewalks that don't connect
    #    (most will - they have different offsets), add a line to connect them.
    pass
