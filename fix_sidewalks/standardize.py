import geopandas as gpd
import pandas as pd


def standardize(streets, sidewalks):
    '''Clean up the streets and sidewalks tables for Seattle into a
    standardized naming scheme.

    :param streets: GeoDataFrame of Seattle's streets in SDOT's spec
    :type streets: geopandas.GeoDataFrame
    :param sidewalks: GeoDataFrame of Seattle's sidewalks in SDOT's spec
    :type sidewalks: geopandas.GeoDataFrame

    '''
    #
    # Standardize the sidewalks table
    #

    df_sw = sidewalks.copy()

    # Separate LineStrings from everything else
    linestrings = df_sw[df_sw.geometry.type == 'LineString']

    # Expand MultiLineStrings into new rows
    newlines = []
    for i, row in df_sw[df_sw.geometry.type == 'MultiLineString'].iterrows():
        for geom in row.geometry:
            # Keep metadata
            newlines.append(row.copy())
            newlines[-1].geometry = geom
    multilinestrings = gpd.GeoDataFrame(newlines)

    # Combine original LineStrings with those from MultiLineStrings
    df_sw = pd.concat([linestrings, multilinestrings])
    df_sw.reset_index(drop=True, inplace=True)

    # Trim columns
    df_sw = df_sw[['SEGKEY', 'CURBRAMPHI', 'CURBRAMPLO', 'geometry']]

    # Extract index from streets table, replace SEGKEY value
    def index_from_compkey(compkey):
        streets_w_compkey = streets[streets['COMPKEY'] == compkey]
        if streets_w_compkey.empty:
            return -1
        else:
            return streets_w_compkey.index[0]

    df_sw['index_st'] = list(df_sw['SEGKEY'].apply(index_from_compkey))
    # Remove sidewalks pointing to nonexistent streets
    df_sw = df_sw[df_sw['index_st'] != -1]
    df_sw.drop('SEGKEY', 1, inplace=True)

    # Rename columns to standardized scheme
    df_sw.rename(columns={'CURBRAMPHI': 'curbramp_end',
                          'CURBRAMPLO': 'curbramp_start'},
                 inplace=True)

    # Dedupe sidewalk lines using WKT (TODO: replace with line similarity)
    df_sw['wkt'] = df_sw.geometry.apply(lambda row: row.wkt)
    df_sw.drop_duplicates(['wkt'], inplace=True)
    df_sw.drop('wkt', 1, inplace=True)

    #
    # Standardize the streets table
    #
    df_st = streets.copy()

    df_st = df_st[['geometry']]
    df_st.crs = streets.crs

    # Dedupe street lines using WKT (TODO: replace with line similarity)
    df_st['wkt'] = df_st.geometry.apply(lambda row: row.wkt)
    df_st.drop_duplicates(['wkt'], inplace=True)
    df_st.drop('wkt', 1, inplace=True)

    #
    # Restore the CRS for both tables
    #
    df_sw.crs = sidewalks.crs
    df_st.crs = sidewalks.crs

    return df_st, df_sw
