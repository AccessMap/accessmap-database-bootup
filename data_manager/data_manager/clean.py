import geopandas as gpd
import numpy as np
import pandas as pd
from shapely import geometry


BUFFER_MIN = 6
BUFFER_MIN2 = BUFFER_MIN**2


def side_of_line(point, linestring):
    '''Given a point and a line, determine which side of the line the point
    is on (from perspective of the line).'''
    # Extract line segment that's closest to the point
    segments = []
    distances = []
    for pair in zip(linestring.coords[:-1], linestring.coords[1:]):
        segment = geometry.LineString(pair)
        segments.append(segment)
        distances.append(segment.distance(point))
    closest = sorted(zip(segments, distances), key=lambda p: p[1])[0][0]

    # Use cross product to determine if sidewalk midpoint is left or right
    # of sidewalk
    # if -1, is on right side
    # if 0, is colinear
    # if 1, is on left side
    x, y = point.coords[0]
    (x1, y1), (x2, y2) = closest.coords
    side = np.sign((x - x1) * (y2 - y1) - (y - y1) * (x2 - x1))

    return side


def sw_tag_streets(df_sw, df_st):
    '''Annotate street GeoDataFrame with two pieces of critical sidewalk
    information in preparation for redrawing sidewalks:
    1) Whethere there is a sidewalk on a given side of the street
    2) The offset distance (in meters) of that sidewalk

    '''
    if df_sw.crs != df_st.crs:
        raise ValueError('Streets and sidewalks must be in same CRS')

    crs = df_sw.crs

    # At this point, the streets GeoDataFrame uses LineStrings, but the
    # sidewalks data frame may be either LineStrings or MultiLineStrings

    #
    # Calculate the distance between every sidewalk and its street
    #

    # Note: offset of 0 = no sidewalk present. A positive numerical value
    # would indicate an offset distance in meters
    df_st['sw_left'] = 0
    df_st['sw_right'] = 0

    for st_index, street in df_st.iterrows():
        # Find the sidewalks associated with this street
        sidewalks = df_sw.loc[df_sw['streets_pkey'] == street['pkey']]

        # Assign every associated sidewalk to the left or right side and
        # calculate the distance
        rights = []
        lefts = []

        for i, sidewalk in sidewalks.iterrows():
            sw_geom = sidewalk.geometry
            midpoint = sw_geom.interpolate(0.5, normalized=True)
            st_projection = street.geometry.project(midpoint)
            st_point = street.geometry.interpolate(st_projection)
            # TODO: Instead of hard-coding default offset, attempt to infer
            # base on neighboring streets
            # Minimum offset
            offset = max(sw_geom.distance(st_point), BUFFER_MIN)

            # Ignore if sidewalk is colinear with its street
            # TODO: replace with faster line similarity algo?
            colinear = True
            if sw_geom.type == 'MultiLineString':
                coords = []
                for geom in sw_geom.geoms:
                    coords += geom.coords
            else:
                coords = sw_geom.coords
            for coord in coords:
                if geometry.Point(coord).distance(street.geometry) > 0.1:
                    colinear = False

            if colinear:
                continue

            # Calculate which side the sidewalk is on
            side = side_of_line(midpoint, street.geometry)
            if side == 0:
                # Somehow still colinear/overlapping at this point, ignore
                continue
            elif side > 0:
                rights.append(offset)
            else:
                lefts.append(offset)

        if lefts:
            df_st.loc[st_index, 'sw_left'] = min(lefts)
        if rights:
            df_st.loc[st_index, 'sw_right'] = min(rights)

    df_st.crs = crs

    return df_st


def redraw_sidewalks(streets):
    '''Given a GeoDataFrame of streets, draw sidewalks at specific offsets.
    Requires that the streets dataframe have 3 columns:
    1) geometry: the LineString geometry of the street
    2) sw_left: 0 if no sidewalk, a positive number indicates the presence and
    offset of the sidewalk on the right side of the street.
    3) sw_right: same as sw_left, but for the right side.

    Returns a new sidewalks GeoDataFrame that includes the original street
    primary key (pkey)

    '''
    crs = streets.crs

    #
    # Draw sidewalks as parallel offsets of streets
    #

    # Simplify streets slightly - removes small jutting out points at end of
    # sidewalks
    streets.geometry = streets.geometry.simplify(0.05)

    # Remove any street endpoints that are extremely short. Short endpoints
    # mess up the redrawing, as they can go in any direction, resulting in
    # large arcs at the end.
    for idx, street in streets.iterrows():
        coords = street.geometry.coords
        len1 = geometry.LineString([coords[0], coords[1]]).length
        len2 = geometry.LineString([coords[-2], coords[-1]]).length

        changed = False
        # 0.5 meters
        cutoff = 0.5
        if len1 < cutoff:
            coords = coords[1:]
            changed = True
        if len2 < cutoff:
            coords = coords[:-1]
            changed = True

        if changed:
            streets.loc[idx, 'geometry'] = geometry.LineString(coords)

    sw_geometries = []
    streets_pkeys = []
    sides = []
    layers = []

    # FIXME: it is almost definitely faster to vector-ize this for loop
    # (and more readable)
    for idx, row in streets.iterrows():
        left = row['sw_left']
        right = row['sw_right']
        if left:
            sw_geometries.append(row.geometry.parallel_offset(left, 'left'))
            sides.append('left')
            streets_pkeys.append(row['pkey'])
            layers.append(row['layer'])
        if right:
            sw_geometries.append(row.geometry.parallel_offset(right, 'right'))
            sides.append('right')
            streets_pkeys.append(row['pkey'])
            layers.append(row['layer'])

    sidewalks = gpd.GeoDataFrame({
        'geometry': sw_geometries,
        'streets_pkey': streets_pkeys,
        'side': sides,
        'layer': layers
    })

    sidewalks = sidewalks.loc[~sidewalks.geometry.is_empty]

    # Remove empty geometries
    sidewalks = sidewalks.loc[~sidewalks.geometry.is_empty]
    sidewalks.reset_index(drop=True, inplace=True)

    sidewalks.crs = crs

    return sidewalks


def buffer_clean(sidewalks, streets):
    #
    # Create street buffers
    #

    # Remove empty geometries
    streets = streets.loc[~streets.geometry.is_empty]
    streets = streets.loc[~streets.geometry.isnull()]

    def buffer_st(row, downscale=0.95):
        # Minimum buffer size (times downscale)
        left = row['sw_left']
        right = row['sw_right']

        if left and right:
            offset = min(left, right)
        elif left:
            offset = left
        elif right:
            offset = right
        else:
            offset = BUFFER_MIN

        return row.geometry.buffer(downscale * offset, cap_style=2)

    buffers = streets.drop('geometry', axis=1)
    buffers['geometry'] = streets.apply(buffer_st, axis=1)
    buffers = gpd.GeoDataFrame(buffers)

    buffers.sindex

    #
    # Trim new sidewalk lines by street buffers
    #

    def trim_by_buffer(sidewalk, buffer_df):
        linestring = sidewalk.geometry
        ixns = buffer_df.sindex.intersection(linestring.bounds, objects=True)
        to_subtract = buffer_df.loc[[x.object for x in ixns]]

        # If 'layer' column in buffer and sidewalk, filter out buffers not on
        # the same vertical layer as the sidewalk in question
        if 'layer' in sidewalk.index and 'layer' in buffer_df.columns:
            same_layer = to_subtract['layer'] == sidewalk['layer']
            to_subtract = to_subtract.loc[same_layer]

        # Subtract off all buffers (cascade method?)
        for i, buffer in to_subtract.geometry.iteritems():
            linestring = linestring.difference(buffer)

        return linestring

    def tbf_apply(row):
        return trim_by_buffer(row, buffers)

    sidewalks['geometry'] = sidewalks.apply(tbf_apply, axis=1)

    # Remove empty geometries
    sidewalks = sidewalks[~sidewalks.geometry.is_empty]
    sidewalks.reset_index(drop=True, inplace=True)

    return sidewalks, buffers


def sanitize(sidewalks):
    crs = sidewalks.crs
    # Separate simple lines (LineStrings) from multi-part MultiLineStrings
    ls = sidewalks.loc[sidewalks.type == 'LineString']
    multi_ls = sidewalks.loc[sidewalks.type == 'MultiLineString']

    # Remove short pieces from MultiLineStrings, update
    min_len = 10
    split = []
    for idx, row in multi_ls.iterrows():
        geoms = row.geometry.geoms
        keep_n = sum([geom.length > min_len for geom in geoms])
        if not keep_n:
            # Keep the longest geom
            newrow = row.copy()
            newrow['geometry'] = sorted(geoms, key=lambda x: x.length)[-1]
            split.append(newrow)
        else:
            # Keep all geoms above length threshold
            for j, geom in enumerate(geoms):
                if geom.length > min_len:
                    newrow = row.copy()
                    newrow['geometry'] = geom
                    split.append(newrow)

    split = gpd.GeoDataFrame(split)

    sidewalks = pd.concat([ls, split])
    sidewalks.reset_index(drop=True, inplace=True)
    sidewalks.crs = crs

    return sidewalks


def snap(sidewalks, streets, threshold=14):
    '''After redrawing sidewalks + cleaning them, the ends may not meet end-to-
    end. This function attempts to trim dangles (intersecting parts that
    overshoot) and connect nearby endpoints that nearly touch.

    '''
    sidewalks = sidewalks.copy()

    #
    # First pass at snapping: connect endpoints if they are:
    #
    # 1) Close together (distance is less than threshold)
    # 2) They aren't on different sides of the same street

    # Isolate sidewalk endpoints (starts and ends) into a new DataFrame
    starts = sidewalks.geometry.apply(lambda x: geometry.Point(x.coords[0]))
    ends = sidewalks.geometry.apply(lambda x: geometry.Point(x.coords[-1]))
    n = sidewalks.shape[0]
    ends = gpd.GeoDataFrame({
        'sw_index': 2 * list(sidewalks.index),
        'streets_pkey': 2 * list(sidewalks['streets_pkey']),
        'side': 2 * list(sidewalks['side']),
        'endtype': n * ['start'] + n * ['end'],
        'geometry': pd.concat([starts, ends])
    })

    ends.reset_index(drop=True, inplace=True)
    # Initialize the spatial index(s) (much faster distance queries)
    ends.sindex
    streets.sindex

    # The selection we want to make is this:
    # Get the closest endpoint to the one we're querying, where the other
    # point is:
    #   (1) within the threshold
    #   (2) the other point is on the same 'block', which could also be
    #       interpreted as there not being a street between them
    #   (3) the other point is not part of the same street - to prevent
    #       snapping of dead end endpoints (which may or may not have
    #       sidewalks - can't determine from typical metadata alone).
    #
    # Strategy:
    #   (1) We want to reuse the spatial index, so we need to do the spatial
    #   query *first*. Therefore, will grab a set of e.g. the 5 nearest
    #   endpoints.
    #   (2) Filter those endpoints by metadata - same street (fast)
    #   (3) Draw line between the remaining points
    #   (4) Filter by line distance (fast) being less than the threshold
    #   (5) Filter by whether the line intersects a street. Use a combination
    #       of spatial index + actual intersection test.
    # Note: this strategy could involve a more optimistic search (e.g.
    #       if the spatial index is much faster than the other steps, could
    #       just iteratively grab next-nearest endpoints until one meets the
    #       conditions or the threshold metric is exceeded.
    # Using -1 as 'no result' placeholder, as pandas DataFrame columns can't
    # handle NaN for integers

    # FIXME: shouldn't average when the angle is ~90 degrees - should find
    # projected intersection point.
    def avg_ends(end1, end2):
        x1, y1 = end1
        x2, y2 = end2
        x = (x1 + x2) / 2
        y = (y1 + y2) / 2
        return (x, y)

    # Track whether a given row has been touched yet
    ends['touched'] = False
    ends['near_id'] = pd.np.nan

    for idx, row in ends.iterrows():
        if row['touched']:
            # Skip if this row has already been snapped (e.g. it was located
            # as the 'other' end and snapped in a previous query)
            continue

        xy = row.geometry.coords[0]
        # Check nearest 2 points only
        sindex_near = ends.sindex.nearest(xy, 3, objects=True)
        candidates = [x.object for x in sindex_near][1:]

        for candidate in candidates:
            other = ends.loc[candidate]

            other_xy = other.geometry.coords[0]
            sindex_other = ends.sindex.nearest(other_xy, 2, objects=True)
            if [x.object for x in sindex_other][1] != idx:
                # There's another, closer endpoint to the other
                # endpoint - we should skip the current row altogether
                # TODO: check whether the bbox-ness of the spatial index could
                # be messing up this check
                break

            same_side = row['side'] == other['side']
            same_street = row['streets_pkey'] == other['streets_pkey']
            if same_street and not same_side:
                # If on same street but opposite side (e.g. dead end), keep
                # looking (skip to the next one)
                continue

            # Line between the endpoints
            between = geometry.LineString([row.geometry, other.geometry])

            # If it's above distance threshold, so are all the others. Skip
            # all of them
            if between.length > threshold:
                break

            # Check if it intersects a street
            ixn = streets.sindex.intersection(between.bounds, objects=True)
            ixn = [x.object for x in ixn]
            if ixn:
                # Bounding boxes intersected - now do real test
                intersects = False
                for st_id in ixn:
                    if streets.loc[st_id].geometry.intersects(between):
                        intersects = True
                        break
                if intersects:
                    # Connecting them would likely interrupt a street - skip
                    # TODO: should probably do a *real* check for intersection
                    # after endpoints would be moved
                    continue

            # If this point has been reached, the candidate has met all of the
            # criteria - fix the geometry and stop searching
            # FIXME: For-loop?
            new = avg_ends(row.geometry.coords[0], other.geometry.coords[0])

            # Update both sidewalks
            for _row in [row, other]:
                swindex = _row['sw_index']
                sw_coords = list(sidewalks.loc[swindex, 'geometry'].coords)

                if _row['endtype'] == 'start':
                    sw_coords[0] = new
                else:
                    sw_coords[-1] = new

                geom = geometry.LineString(sw_coords)

                sidewalks.loc[_row['sw_index'], 'geometry'] = geom

            break

    return sidewalks
