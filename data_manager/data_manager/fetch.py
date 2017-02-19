import requests
import zipfile
from StringIO import StringIO
import os


def fetch_shapefile(url, shapefile, outpath, name):
        # Download based on source.json layer url
        response = requests.get(url)
        zipper = zipfile.ZipFile(StringIO(response.content), 'r')
        found_any = False
        # Filter by files matching source.json layer 'shapefile' key
        for member in zipper.namelist():
            path, ext = member.split(os.extsep, 1)
            if shapefile in path:
                # Extract to standard naming scheme, e.g. layer.shp
                found_any = True
                f = zipper.open(member)
                write_path = os.path.join(outpath, '{}.{}'.format(name, ext))

                with open(write_path, 'w') as g:
                    g.write(f.read())

        if not found_any:
            raise Exception('Could not find matching files in zip archive.')
