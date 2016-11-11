import geopandas as gpd
from fix_sidewalks import clean, standardize


def fix_schema(streets, sidewalks):
    streets, sidewalks = standardize.standardize(streets, sidewalks)
    return streets, sidewalks

if __name__ == '__main__':
    import os
    import sys

    print 'Reading files'
    streets = gpd.read_file(sys.argv[1])
    sidewalks = gpd.read_file(sys.argv[2])

    print 'Standardizing data schema'
    streets, sidewalks = fix_schema(streets, sidewalks)

    print 'Reprojecting'
    streets = clean.reproject(streets)
    sidewalks = clean.reproject(sidewalks)

    print 'Assigning sidewalk side to streets'
    sidewalks = clean.sw_tag_streets(sidewalks, streets)

    print 'Drawing sidewalks'
    sidewalks = clean.redraw_sidewalks(sidewalks, streets)

    print 'Cleaning with street buffers'
    sidewalks, buffers = clean.buffer_clean(sidewalks, streets)

    print 'Sanitizing sidewalks'
    sidewalks = clean.sanitize(sidewalks)

    print 'Snapping sidewalk ends'
    sidewalks = clean.snap(sidewalks, streets)

    print 'Writing to file'
    if not os.path.exists('./clean'):
        os.mkdir('./clean')

    streets.to_file('./clean/streets.shp')
    sidewalks.to_file('./clean/sidewalks.shp')
