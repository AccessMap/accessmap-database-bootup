'''Handle data fetching/cleaning tasks automatically. Reads and writes from a
pseudo-database in the filesystem, organized as ./cities/<city>/

'''

import json
import os

import click
import geopandas as gpd

from .annotate import annotate_line_from_points
from . import fetchers
from . import dems
from . import clean as sidewalk_clean
from . import make_crossings
from .standardize import standardize_df, assign_st_to_sw, whitelist_filter


BASE = os.path.abspath('./cities')


def get_metadata(city):
    with open(os.path.join(BASE, city, 'sources.json')) as f:
        return json.load(f)


def get_data(city, layername, category):
    path = os.path.join(BASE, city, category, '{}.shp'.format(layername))
    return gpd.read_file(path)


def put_data(gdf, city, layername, category, delete=False):
    directory = os.path.join(BASE, city, category)
    if not os.path.exists(directory):
        os.mkdir(directory)

    writepath = os.path.join(directory, '{}.shp'.format(layername))
    # write to temp dir and then move? Prevents loss of old data if write fails
    if delete:
        if os.path.exists(writepath):
            os.remove(directory)
    gdf.to_file(writepath)


@click.group()
def cli():
    pass


@cli.command()
@click.argument('city')
def fetch(city):
    # If this command is being called on its own, fetch the data + write to
    # directory structure under cities/<city>/original/layername.shp
    metadata = get_metadata(city)
    layers = fetchers.fetch(metadata)
    # Iterate over each layer and write to file
    for name, gdf in layers.items():
        put_data(gdf, city, name, 'original')


@cli.command()
@click.argument('city')
def fetch_dem(city):
    '''Fetch DEM (elevation) data for the area of interest. Data is output to
    cities/<city>/dem/region, where region is e.g. n48w123.

    '''
    metadata = get_metadata(city)
    outdir = os.path.join(BASE, city, 'dems')
    if not os.path.exists(outdir):
        os.mkdir(outdir)

    click.echo('Reading in vector data...')
    layernames = metadata['layers'].keys()
    gdfs = [get_data(city, layername, 'original') for layername in layernames]

    click.echo('Downloading DEMs...')
    dems.dem_workflow(gdfs, outdir)


def standardize(city):
    click.echo('Standardizing data schema')

    click.echo('    Loading metadata...')
    with open(os.path.join(BASE, city, 'sources.json')) as f:
        sources = json.load(f)
        layers = sources['layers'].keys()

        # Require streets input
        if 'streets' not in sources['layers']:
            raise ValueError('streets data source required')
        elif 'metadata' not in sources['layers']['streets']:
            raise ValueError('streets data source must have metadata')
        st_metadata = sources['layers']['streets']['metadata']

        # Require sidewalks input
        if 'sidewalks' not in sources['layers']:
            raise ValueError('sidewalks data source required')
        elif 'metadata' not in sources['layers']['sidewalks']:
            raise ValueError('sidewalks data source must have metadata')
        sw_metadata = sources['layers']['sidewalks']['metadata']

        # Require a foreign key between sidewalks and streets
        if ('pkey' not in st_metadata) or ('streets_pkey' not in sw_metadata):
            raise Exception('Sidewalks must have foreign key to streets'
                            'dataset and streets must have primary key')

    click.echo('    Reading input data...')
    outpath = os.path.join(BASE, city, 'standardized')
    if not os.path.exists(outpath):
        os.mkdir(outpath)

    frames = {}
    for layer in sources['layers'].keys():
        frames[layer] = get_data(city, layer, 'original')

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

    # TODO: move this to separate function
    click.echo('Generating crossings...')
    crossings = make_crossings.make_graph(sidewalks, streets)
    if crossings.empty:
        raise Exception('Generated no crossings')
    else:
        put_data(crossings, city, 'crossings', 'clean')

    click.echo('Writing to file...')
    put_data(sidewalks, city, 'sidewalks', 'clean')
    if 'curbramps' in frames:
        put_data(frames['curbramps'], city, 'curbramps', 'clean')


@cli.command()
@click.argument('city')
def annotate(city):
    click.echo('Standardizing data schema')

    click.echo('    Loading metadata...')
    with open(os.path.join(BASE, city, 'sources.json')) as f:
        sources = json.load(f)

        frames = {}
        layers = ['sidewalks', 'crossings']
        for layer in layers:
            frames[layer] = get_data(city, layer, 'clean')

        # Also add crossings...
        frames['crossings'] = get_data(city, 'crossings', 'clean')

        annotations = sources.get('annotations')
        if annotations is not None:
            click.echo('Annotating...')
            for name, annotation in annotations.items():
                # Fetch the annotations
                click.echo('Downloading {}...'.format(name))
                url = annotation['url']
                click.echo(url)
                gdf = fetchers.fetch_shapefile(url, annotation['shapefile'])

                # Reproject
                gdf = gdf.to_crs({'init': 'epsg:26910'})

                # Apply appropriate functions, overwrite layers in 'clean' dir
                # FIXME: hard-coded sidewalks here
                annotate_line_from_points(frames['crossings'], gdf,
                                          annotation['default_tags'])
                put_data(frames['crossings'], city, 'crossings', 'annotated')


@cli.command()
@click.argument('city')
@click.pass_context
def fetch_all(ctx, city):
    ctx.forward(fetch)
    ctx.forward(fetch_dem)


@cli.command()
@click.argument('city')
@click.pass_context
def all(ctx, city):
    ctx.forward(fetch)
    ctx.forward(fetch_dem)
    ctx.forward(clean)
    ctx.forward(annotate)


if __name__ == '__main__':
    cli()
