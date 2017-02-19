import requests
import zipfile
import StringIO
import os

# 1) Downloads source files
# 2) Unzips them in memory
# 3) Writes them to file, renaming them in the process


def fetch_zip(url):
    response = requests.get(url)
    zipper = zipfile.ZipFile(StringIO(response.content), 'r')

    return zipper


def fetch_shapefile(url, unzipped_path, outpath, name):
    found_any = False
    zipper = fetch_zip(url)
    for member in zipper.namelist():
        path, ext = member.split(os.extsep, 1)
        if unzipped_path in path:
            # Extract to standard naming scheme, e.g. layer.shp
            found_any = True
            f = zipper.open(member)
            write_path = os.path.join(outpath, '{}.{}'.format(name, ext))

            with open(write_path, 'w') as g:
                g.write(f.read())

    if not found_any:
        raise Exception('Could not find matching files in zip archive.')
