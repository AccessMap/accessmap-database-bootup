'''Handle data fetching/cleaning tasks automatically. Reads and writes from a
pseudo-database in the filesystem, organized as ./cities/<city>/

'''

import click
import json
import geopandas as gpd
import os
import shutil
import zipfile
from StringIO import StringIO
from . import clean as sidewalk_clean
from .standardize import standardize_df, assign_st_to_sw, whitelist_filter


BASE = os.path.abspath('./cities')


@click.group()
def cli():
    pass


@cli.command()
@click.argument('city')
def fetch(city):
    import requests

    with open(os.path.join(BASE, city, 'sources.json')) as f:
        sources = json.load(f)

    outpath = os.path.join(BASE, city, 'original')
    if not os.path.exists(outpath):
        os.mkdir(outpath)

    # Iterate over each layer, download + unzip to standard naming scheme
    layers = sources.keys()
    for layer in layers:
        click.echo('Downloading {}...'.format(layer))
        click.echo(sources[layer]['url'])
        # Download based on source.json layer url
        response = requests.get(sources[layer]['url'])
        zipper = zipfile.ZipFile(StringIO(response.content), 'r')
        found_any = False
        # Filter by files matching source.json layer 'shapefile' key
        for member in zipper.namelist():
            path, ext = member.split(os.extsep, 1)
            if sources[layer]['shapefile'] in path:
                # Extract to standard naming scheme, e.g. layer.shp
                found_any = True
                f = zipper.open(member)
                write_path = os.path.join(outpath, '{}.{}'.format(layer, ext))

                with open(write_path, 'w') as g:
                    g.write(f.read())

        if not found_any:
            raise Exception('Could not find matching files in zip archive.')


@cli.command()
@click.argument('city')
def dem(city):
    from shapely import geometry
    import requests
    '''Fetch DEM (elevation) data for the city of interest.'''
    click.echo('Calculating extent of pedestrian features...')

    with open(os.path.join(BASE, city, 'sources.json')) as f:
        sources = json.load(f)

    # Base url for DEM data
    data_url = ('https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/13/'
                'ArcGrid/{ns}{lat}{ew}{lon}.zip')
    # Figure out which files are needed - get extent of shapefiles
    layers = sources.keys()
    inpath = os.path.join(BASE, city, 'original')
    outpath = os.path.join(BASE, city, 'dem')

    # frames = []

    boundset = []
    for layer in layers:
        filepath = os.path.join(inpath, '{}.shp'.format(layer))
        frame = gpd.read_file(filepath).dropna(axis=0, subset=['geometry'])
        crs = frame.crs

        # Filter out invalid geometries
        # FIXME: This should be done more carefully - e.g. compare data to
        # exact dimensions of the projection

        def valid(bounds, limit=1e10):
            for bound in bounds:
                if bound > limit or bound < (-1 * limit):
                    return False
            return True
        frame = frame.loc[frame.bounds.apply(valid, axis=1)]
        bounds = frame.geometry.total_bounds
        boundset.append(bounds)

        # frame = frame.to_crs({'init': 'epsg:4326'})
        # frames.append(frame)

    # Find the extents
    # boundset = gpd.GeoSeries([frame.geometry.total_bounds for frame
    #                           in frames])

    # Find the bounding box of the whole thing
    west = min([b[0] for b in boundset])
    south = min([b[1] for b in boundset])
    east = max([b[2] for b in boundset])
    north = max([b[3] for b in boundset])

    rect = geometry.Polygon([(west, south), (west, north), (east, north),
                             (east, south)])
    rectseries = gpd.GeoSeries([rect])
    rectseries.crs = crs
    rect = rectseries.to_crs({'init': 'epsg:4326'})[0]

    # Figure out which DEMs are needed
    regions = []
    # NED naming scheme orders lons from negative to positive
    for i in range(-180, 180):
        # NED naming scheme orders lons from positive to negative
        for j in reversed(range(-89, 91)):
            geom = geometry.Polygon([(i, j - 1), (i, j), (i + 1, j),
                                     (i + 1, j - 1)])

            regions.append({
                'geometry': geom,
                'lon': abs(i),
                'lat': abs(j),
                'ew': 'w' if i < 0 else 'e',
                'ns': 's' if j < 0 else 'n'
            })

    regions = gpd.GeoDataFrame(regions)

    to_download = regions[regions.intersects(rect)]

    # Actually download the files
    if not os.path.exists(outpath):
        os.mkdir(outpath)

    for i, row in to_download.iterrows():
        ns = row['ns']
        ew = row['ew']
        lat = row['lat']
        lon = row['lon']
        description = '{}{}{}{}'.format(ns, lat, ew, lon)
        click.echo('Downloading {}...'.format(description))
        url = data_url.format(ns=ns, ew=ew, lat=lat, lon=lon)
        # TODO: add progress bar using stream argument + click progress bar
        response = requests.get(url)
        # Filter by files matching source.json layer 'shapefile' key
        dempath = os.path.join(outpath, description)
        if not os.path.exists(dempath):
            os.mkdir(dempath)

        zipper = zipfile.ZipFile(StringIO(response.content), 'r')
        extract_dir = 'grd{}_13/'.format(description)

        for path in zipper.namelist():
            if extract_dir in path:
                if extract_dir == path:
                    continue
                extract_path = os.path.join(dempath, os.path.basename(path))
                with zipper.open(path) as f:
                    with open(extract_path, 'w') as g:
                        g.write(f.read())


# @cli.command()
# @click.argument('city')
def standardize(city):
    click.echo('Standardizing data schema')

    click.echo('    Loading metadata...')
    with open(os.path.join(BASE, city, 'sources.json')) as f:
        sources = json.load(f)
        layers = sources.keys()

        # Require streets input
        if 'streets' not in sources:
            raise ValueError('streets data source required')
        elif 'metadata' not in sources['streets']:
            raise ValueError('streets data source must have metadata')
        st_metadata = sources['streets']['metadata']

        # Require sidewalks input
        if 'sidewalks' not in sources:
            raise ValueError('sidewalks data source required')
        elif 'metadata' not in sources['sidewalks']:
            raise ValueError('sidewalks data source must have metadata')
        sw_metadata = sources['sidewalks']['metadata']

        # Require a foreign key between sidewalks and streets
        if ('pkey' not in st_metadata) or ('streets_pkey' not in sw_metadata):
            raise Exception('Sidewalks must have foreign key to streets'
                            'dataset and streets must have primary key')

    click.echo('    Reading input data...')
    inpath = os.path.join(BASE, city, 'original')
    outpath = os.path.join(BASE, city, 'standardized')
    if not os.path.exists(outpath):
        os.mkdir(outpath)

    frames = {}
    for layer in layers:
        path = os.path.join(inpath, '{}.shp'.format(layer))
        frames[layer] = gpd.read_file(path)

    click.echo('    Running standardization scripts...')
    # Standardize GeoDataFrame columns
    frames['streets'] = standardize_df(frames['streets'], st_metadata)
    frames['sidewalks'] = standardize_df(frames['sidewalks'], sw_metadata)

    # Require that streets to simple LineString geometries to simplify process
    # of assigning sidewalks to streets
    if (frames['streets'].geometry.type != 'LineString').sum():
        raise ValueError('streets dataset must be use simple LineStrings')

    # Filter streets to just those that matter for sidewalks (excludes, e.g.,
    # rail and highways).

    # Used to include 'motorway_link', but unfortunately the 'level' (z-level)
    # is not correctly logged, so it's impossible to know whether a given
    # highway entrance/exit segment is grade-separated. Erring on the side of
    # connectivity for now.
    st_whitelists = {
        'waytype': ['street']
    }
    frames['streets'] = whitelist_filter(frames['streets'], st_whitelists)

    # Assign street foreign key to sidewalks, remove sidewalks that don't refer
    # to a street
    click.echo('    Assigning sidewalks to streets...')
    frames['sidewalks'] = assign_st_to_sw(frames['sidewalks'],
                                          frames['streets'])

    for layer in layers:
        # Project to SRID 26910 (NAD83 for WA in meters)
        # FIXME: this shouldn't be hardcoded, should be determined from extent
        # May also need to ask for projection from user, if dataset doesn't
        # report it (or reports it incorrectly)
        # FIXME: Use non-NAD83?
        click.echo('    Reprojecting to srid 26910...')
        srid = '26910'
        frame = frames[layer]

        # Reprojection creates an error for empty geometries - they must
        # be removed first
        frame = frame.dropna(axis=0, subset=['geometry'])
        # frame = frame[~frame.geometry.is_empty]
        # frame = frame[~frame['geometry'].isnull()]

        # Reproject
        frame = frame.to_crs({'init': 'epsg:{}'.format(srid)})

        frames[layer] = frame

        # May need to overwrite files, but Fiona (used by GeoPandas) can't do
        # that sometimes, so remove first
        # click.echo('    Writing file...')
        # for filepath in os.listdir(outpath):
        #     if filepath.split(os.extsep, 1)[0] == layer:
        #         os.remove(os.path.join(outpath, filepath))

        # # Write back to the same files
        # # TODO: Make writing to file non-blocking (threads?)
        # frame.to_file(os.path.join(outpath, '{}.shp'.format(layer)))
    click.echo('done')
    return frames


@cli.command()
@click.argument('city')
def clean(city):
    frames = standardize(city)
    outpath = os.path.join(BASE, city, 'clean')
    # if not os.path.exists(outpath):
    #     os.mkdir(outpath)

    streets = frames['streets']
    sidewalks = frames['sidewalks']

    click.echo('Assigning sidewalk side to streets...')
    streets = sidewalk_clean.sw_tag_streets(sidewalks, streets)

    click.echo('Drawing sidewalks...')
    sidewalks = sidewalk_clean.redraw_sidewalks(streets)

    # click.echo('Cleaning with street buffers...')
    sidewalks, buffers = sidewalk_clean.buffer_clean(sidewalks, streets)

    # click.echo('Sanitizing sidewalks...')
    sidewalks = sidewalk_clean.sanitize(sidewalks)

    click.echo('Snapping sidewalk ends...')
    # This step is slow - profile it!
    sidewalks = sidewalk_clean.snap(sidewalks, streets)

    click.echo('Writing to file...')
    streets.to_file(os.path.join(outpath, 'streets.shp'))
    sidewalks.to_file(os.path.join(outpath, 'sidewalks.shp'))

    # FIXME: curbramps should go through its own standardization/cleanup
    # workflow
    inpath = os.path.join(BASE, city, 'original')
    for path in os.listdir(inpath):
        filename = os.path.basename(path)
        if path.split(os.extsep, 1)[0] == 'curbramps':
            shutil.copy2(os.path.join(inpath, path),
                         os.path.join(BASE, city, 'clean', filename))


@cli.command()
@click.argument('city')
@click.pass_context
def all(ctx, city):
    ctx.forward(fetch)
    ctx.forward(dem)
    ctx.forward(standardize)
    ctx.forward(clean)


if __name__ == '__main__':
    cli()
