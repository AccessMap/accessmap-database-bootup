import geopandas as gpd
import numpy as np
import pandas as pd
from shapely import geometry


def reproject(df, projection='26910'):
    return df.to_crs({'init': 'epsg:26910'})


def sw_tag_streets(sidewalks, streets):
    sidewalks = sidewalks.copy()
    streets = streets.copy()

    #
    # Calculate the distance between every sidewalk and it street
    #

    # Calculate the midpoint, find the associated street geometry and its
    # closest point
    sidewalks['midpoint'] = sidewalks.interpolate(0.5, normalized=True)
    st_by_sw = streets.loc[list(sidewalks['index_st'])].geometry
    sidewalks['st_geometry'] = list(st_by_sw)

    sidewalks = sidewalks[~sidewalks.geometry.is_empty]
    sidewalks = sidewalks[~sidewalks['geometry'].isnull()]
    sidewalks = sidewalks[~sidewalks['st_geometry'].isnull()]

    def closest_point(point, linestring):
        return linestring.interpolate(linestring.project(point))

    def cp_apply(row):
        return closest_point(row['midpoint'], row['st_geometry'])

    sidewalks['nearpoint_st'] = sidewalks.apply(cp_apply, axis=1)

    def sw_st_dist(row):
        return max(row.geometry.distance(row['st_geometry']), 4)

    sidewalks['offset'] = sidewalks.apply(sw_st_dist, axis=1)

    # Remove sidewalks that are colinear with their street
    def colinear_sw(row):
        sw = row['geometry']
        st = row['st_geometry']
        for coord in sw.coords:
            # 10 centimeters
            if geometry.Point(coord).distance(st) > 0.1:
                return False
        return True

    colinear = sidewalks.apply(colinear_sw, axis=1)
    sidewalks = sidewalks[~colinear]

    #
    # Calculate which side the sidewalk is on
    #
    def line_under_point(point, linestring):
        # Split linestring into segments, find closest one
        segments = []
        distances = []
        for pair in zip(linestring.coords[:-1], linestring.coords[1:]):
            segment = geometry.LineString(pair)
            segments.append(segment)
            distances.append(segment.distance(point))
        return sorted(zip(segments, distances), key=lambda p: p[1])[0][0]

    def lup_apply(row):
        return line_under_point(row['nearpoint_st'], row['st_geometry'])

    sidewalks['st_seg'] = sidewalks.apply(lup_apply, axis=1)

    def line_side(point, line):
        # Use cross product to determine if sidewalk midpoint is left or right
        # of sidewalk
        # if -1, is on right side
        # if 0, is colinear
        # if 1, is on left side
        x, y = point.coords[0]
        (x1, y1), (x2, y2) = line.coords
        return np.sign((x - x1) * (y2 - y1) - (y - y1) * (x2 - x1))

    def ls_apply(row):
        return line_side(row['midpoint'], row['st_seg'])

    sidewalks['side'] = sidewalks.apply(ls_apply, axis=1)

    # Drop sidewalks that are colinear - that's messed up!
    sidewalks = sidewalks[sidewalks['side'] != 0]

    # Replace numbers with text label
    sidewalks['side'] = sidewalks['side'].apply(lambda x: 'right' if x > 0 else
                                                'left')

    # Go back to streets and update
    # def sw_side_of_street(group):
    #     sides = group['side']
    #     right = 'right' in sides.values
    #     left = 'left' in sides.values
    #     if right:
    #         if left:
    #             label = 'both'
    #         else:
    #             label = 'right'
    #     elif left:
    #         label = 'left'
    #     else:
    #         label = 'none'

    #     return pd.DataFrame({
    #         'side': [label],
    #         'offset': [group['offset'].min()],
    #         'index_st': [group['index_st'].iloc[0]]
    #     }, index=group.index)

    # sides = sidewalks.groupby('index_st').apply(sw_side_of_street)

    # sides = sides.set_index('index_st').loc[streets.index]
    # sides = sides.drop_duplicates()
    # streets['offset'] = sides['offset'].apply(lambda x: max(x, 4))
    # streets['sidewalk'] = sides['side']
    # streets['offset'] = streets['offset'].fillna(0)
    # streets['sidewalk'] = streets['sidewalk'].fillna('none')
    # streets.reset_index(drop=True, inplace=True)

    return sidewalks


def redraw_sidewalks(sidewalks, streets):
    #
    # Draw sidewalks as parallel offsets of streets
    #

    # Simplify streets slightly - removes small jutting out points at end of
    # sidewalks
    streets.geometry = streets.geometry.simplify(0.05)

    # Takes about 1.5 minutes
    rows = []
    # Use streets with a valid geometry only
    sidewalks = sidewalks[sidewalks['st_geometry'].astype(bool)]
    for idx, row in sidewalks.iterrows():
        queue = []
        st_geom = streets.loc[row['index_st']].geometry
        if row['side'] == 'both':
            queue.append(st_geom.parallel_offset(row['offset'], 'left'))
            queue.append(st_geom.parallel_offset(row['offset'], 'right'))
        elif row['side'] == 'left':
            queue.append(st_geom.parallel_offset(row['offset'], 'left'))
        elif row['side'] == 'right':
            queue.append(st_geom.parallel_offset(row['offset'], 'right'))

        for geom in queue:
            df = gpd.GeoDataFrame({'geometry': [geom],
                                   'index_st': row['index_st'],
                                   'curbramp_start': row['curbramp_start'],
                                   'curbramp_end': row['curbramp_end'],
                                   'offset': row['offset']})
            rows.append(df)

    crs = sidewalks.crs
    sidewalks = pd.concat(rows)
    sidewalks = sidewalks[~sidewalks.geometry.is_empty]
    sidewalks.crs = crs

    # Remove empty geometries
    sidewalks = sidewalks[~sidewalks.geometry.is_empty]
    sidewalks.reset_index(drop=True, inplace=True)

    return sidewalks


def buffer_clean(sidewalks, streets):
    sidewalks = sidewalks.copy()
    streets = streets.copy()
    #
    # Create street buffers
    #

    # Default to 4 meter buffer, use sidewalk offset data if available
    streets['offset'] = 4
    for idx, group in sidewalks.groupby('index_st'):
        # Use min offset
        offset = group['offset'].min()
        # There are occasional unexpected errors where sidewalks are assigned
        # to streets that are way too far away. When this occurs, they should
        # not be drawn (offset = 0)
        if offset > 20:
            offset = 0
        streets.loc[idx, 'offset'] = offset

    # Remove empty geometries
    streets = streets[~streets.geometry.is_empty]
    streets = streets[~streets.geometry.isnull()]

    # Remove 0-offset buffers
    streets = streets[streets['offset'] != 0]

    def buffer_st(row, downscale=0.90):
        return row.geometry.buffer(downscale * row['offset'])

    buffers = gpd.GeoDataFrame({
        'geometry': streets.apply(buffer_st, axis=1)
    })
    buffers.sindex

    #
    # Trim new sidewalk lines by street buffers
    #

    def trim_by_buffer(linestring, buffer_df):
        ixns = buffer_df.sindex.intersection(linestring.bounds, objects=True)
        buffer_ids = [x.object for x in ixns]

        # Subtract off all buffers
        for i, buffered in buffer_df.loc[buffer_ids].geometry.iteritems():
            linestring = linestring.difference(buffered)
        return linestring

    def tbf_apply(row):
        ls = trim_by_buffer(row.geometry, buffers)
        copy = row.copy()
        copy['geometry'] = ls
        return copy

    sidewalks_trimmed = gpd.GeoDataFrame(sidewalks.apply(tbf_apply, axis=1))
    sidewalks.update(sidewalks_trimmed)

    # Remove empty geometries
    sidewalks = sidewalks[~sidewalks.geometry.is_empty]
    sidewalks.reset_index(drop=True, inplace=True)

    return sidewalks, buffers


def sanitize(sidewalks):
    # Separate simple lines (LineStrings) from multi-part MultiLineStrings
    # ls = sidewalks[sidewalks.type == 'LineString']
    crs = sidewalks.crs
    # sidewalks = gpd.GeoDataFrame(sidewalks)

    multi_ls = sidewalks[sidewalks.type == 'MultiLineString']

    # Remove short pieces from MultiLineStrings, update
    min_len = 10
    ls = []
    for idx, row in multi_ls.iterrows():
        geoms = row.geometry.geoms
        keep_n = sum([geom.length > min_len for geom in geoms])
        if not keep_n:
            # Keep the longest geom
            newrow = row.copy()
            newrow['geometry'] = sorted(geoms, key=lambda x: x.length)[-1]
            ls.append(newrow)
        else:
            # Keep all geoms above length threshold
            n = len(geoms)
            for j, geom in enumerate(geoms):
                if geom.length > min_len:
                    newrow = row.copy()
                    newrow['geometry'] = geom
                    newrow['curbramp_start'] = 'N'
                    newrow['curbramp_end'] = 'N'
                    if j == 0:
                        newrow['curbramp_start'] = 'Y'
                    elif j == (n - 1):
                        newrow['curbramp_end'] = 'Y'
                    ls.append(newrow)

    # FIXME: bug encountered attempting to setitem in pandas dataframe
    # with MultiLineString - report upstream!
    # sidewalks.loc[idx, 'geometry'] = geom

    multi = gpd.GeoDataFrame(ls)
    single = sidewalks[sidewalks.type == 'LineString']

    sidewalks = pd.concat([single, multi])
    sidewalks.reset_index(drop=True, inplace=True)
    sidewalks.crs = crs

    return sidewalks


def snap(sidewalks, streets, short_dist=2, long_dist=12):
    sidewalks = sidewalks.copy()
    streets = streets.copy()
    # Snap behavior - need to locate sidewalk ends within a certain distance
    starts = sidewalks.geometry.apply(lambda x: geometry.Point(x.coords[0]))
    ends = sidewalks.geometry.apply(lambda x: geometry.Point(x.coords[-1]))
    n = sidewalks.shape[0]
    ends = gpd.GeoDataFrame({
        'sidewalk_index': 2 * list(sidewalks.index),
        'endtype': n * ['start'] + n * ['end'],
        'geometry': pd.concat([starts, ends])
    })

    ends.reset_index(drop=True, inplace=True)

    ends.sindex
    # FIXME: should do the 'without crossing a street' check here so we can
    # get the closest reasonable sidewalk end

    def nearest_end(row):
        xy = row.geometry.coords[0]
        match2 = list(ends.sindex.nearest(xy, 2, objects=True))[1]
        end_index = match2.object

        return end_index

    ends['near_index'] = ends.apply(nearest_end, axis=1)
    ends['near_type'] = list(ends.loc[ends['near_index']]['endtype'])
    ends['near_geom'] = list(ends.loc[ends['near_index']].geometry)

    def near_dist(row):
        return row.geometry.distance(row['near_geom'])

    ends['near_dist'] = ends.apply(near_dist, axis=1)

    # If the snaps are close together, use simple averaging to snap them
    # together
    def simple_snap(row):
        x1, y1 = row.geometry.coords[0]
        x2, y2 = row['near_geom'].coords[0]
        x = (x1 + x2) / 2
        y = (y1 + y2) / 2
        snapped = geometry.Point([x, y])

        return snapped

    simple_tosnap = ends[(ends['near_dist'] < short_dist) &
                         (ends['near_dist'] > 0)]
    snapped_geoms = simple_tosnap.apply(simple_snap, axis=1)
    ends_snapped = snapped_geoms.to_frame('geometry')
    ends_snapped['near_dist'] = 0.0
    ends.update(ends_snapped)

    # For ends farther apart, need to be more sopohisticated
    # TODO: optimize this step - many redundant shapely operations
    streets.sindex

    def snap(row):
        # Strategy: use midpoint if lines are parallel, use intersection
        #           point if they're orthogonal, and linearly scale between

        # Note: expectation is that this is a group of shape (2, n)

        # Get the sidewalk linestrings corresponding to this row
        other = ends.loc[row['near_index']]

        # Check for symmetry! If these aren't closest to each other, could
        # cause issues
        if row.name != other['near_index']:
            return row.geometry

        def azimuth(p1, p2):
            radians = np.arctan2(p2[0] - p1[0], p2[1] - p1[1])
            if radians < 0:
                radians += np.pi
            return radians

        # Need to look up sidewalks in order to calculate
        # azimuth / intersection points
        segments = []
        azimuths = []

        for end in [row, other]:
            s = sidewalks.loc[end['sidewalk_index']]
            s_type = end['endtype']
            if s_type == 'start':
                # Get the first 2 points
                segment = geometry.LineString(reversed(s.geometry.coords[:2]))
            else:
                # Get the last 2 points
                segment = geometry.LineString(s.geometry.coords[-2:])
            segments.append(segment)
            azimuths.append(azimuth(segment.coords[0], segment.coords[1]))

        # Find the difference in azimuth + the intersection
        dazimuth = abs(azimuths[1] - azimuths[0])

        # The 'sin' function is close to what we want - ~0 when
        # dazimuth is ~0 or ~pi (parallel) and ~1 when ~orthogonal
        scale = np.sin(dazimuth)

        def intersection(segment1, segment2):
            # Given two line segments, find the intersection
            # point between their representative lines
            def line(segment):
                # Given a line segment, find the line (mx + b)
                # parameters m and b
                xs, ys = segment.xy
                m = (ys[1] - ys[0]) / (xs[1] - xs[0])
                b = ys[0] - (m * xs[0])
                return (m, b)

            m1, b1 = line(segment1)
            m2, b2 = line(segment2)

            x = (b2 - b1) / float((m1 - m2))
            y = m1 * x + b1

            return geometry.Point(x, y)

        if scale < 0.2:
            # They're parallelish, use midpoint
            p1 = row.geometry
            p2 = other.geometry
            point = geometry.Point([(p1.x + p2.x) / 2, (p1.y + p2.y) / 2])
        elif scale > 0.8:
            # They're orthogonalish, use intersection
            point = intersection(*segments)
        else:
            # They're in between - use weighted average
            p1 = row.geometry
            p2 = other.geometry
            mid = geometry.Point([(p1.x + p2.x) / 2, (p1.y + p2.y) / 2])
            ixn = intersection(*segments)

            midx, midy = [scale * coord for coord in mid.coords[0]]
            ixnx, ixny = [(1 - scale) * coord for coord in ixn.coords[0]]

            point = geometry.Point([midx + ixnx, midy + ixny])

        # Finally, ensure that new geometries don't intersect streets
        l1 = geometry.LineString([row.geometry, point])
        l2 = geometry.LineString([other.geometry, point])

        for line in [l1, l2]:
            st_ixn = streets.sindex.intersection(l1.bounds, objects=True)
            bound_ixn = [x.object for x in st_ixn]
            if bound_ixn:
                if streets.loc[bound_ixn].intersects(line).any():
                    return row.geometry
        return point

    # FIXME: if long_dist is increased, we end up with dead end sidewalks
    # being connected (when they shouldn't be, by default).
    # Idea: detect 'dead-end' streets nearby/between the sidewalks and don't
    # connect if they exist
    # Alternative: the gaps that still need fixing are T-intersections. They
    # happen because the buffers endcaps can extend past streets at a T
    # intersection and impact the wrong sidewalks. A more nuanced buffer
    # system would help
    nearby = ends['near_dist'] < long_dist
    nonzero = ends['near_dist'] > 0
    ends_tosnap = ends[nearby & nonzero]
    ends_snapped = ends_tosnap.apply(snap, axis=1).to_frame('geometry')
    ends.update(ends_snapped)

    # Rewrite every start + end point
    def move_sidewalk(row):
        sw_ends = ends[ends['sidewalk_index'] == row.name]
        if not sw_ends.empty:
            coords = list(row.geometry.coords)
            for i, end in sw_ends.iterrows():
                if end['endtype'] == 'start':
                    coords[0] = end.geometry.coords[0]
                else:
                    coords[-1] = end.geometry.coords[0]
            return geometry.LineString(coords)
        else:
            return row.geometry

    snapped_lines = sidewalks.apply(move_sidewalk, axis=1).to_frame('geometry')
    sidewalks.update(snapped_lines)

    return sidewalks
