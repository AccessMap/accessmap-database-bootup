import geopandas as gpd
import numpy as np
from shapely import geometry
import networkx as nx

from .utils import azimuth


def create_graph(path, precision=1):
    '''Create a networkx DiGraph given a GeoDataFrame of lines. Every line will
    correspond to two directional graph edges, one forward, one reverse. The
    original line row and direction will be stored in each edge. Every node
    will be where endpoints meet (determined by being very close together) and
    will store a clockwise ordering of incoming edges.

    '''
    # TODO: roll our own nx.read_shp that removes data we don't need from the
    # get-go (and potentially groups nodes at the same time).
    gdf = gpd.read_file(path)

    G = nx.DiGraph()
    # Edges are stored as (from, to, data), where from and to are nodes.
    for idx, row in gdf.iterrows():
        geom = row.geometry
        start = tuple(np.round(geom.coords[0], precision))
        end = tuple(np.round(geom.coords[-1], precision))

        # Add forward edge
        fwd_attr = {
            'forward': 1,
            'geometry': geom,
            'azimuth': azimuth(geom.coords[-2], geom.coords[-1]),
            'sidewalk': row.sw_right,
            'id': row.id
        }
        G.add_edge(start, end, fwd_attr)

        # Add reverse edge
        rev_attr = {
            'forward': 0,
            'geometry': geometry.LineString(geom.coords[::-1]),
            'azimuth': azimuth(geom.coords[1], geom.coords[0]),
            'sidewalk': row.sw_left,
            'id': row.id
        }
        G.add_edge(end, start, rev_attr)

    return G


def process_acyclic(G):
    paths = []
    while True:
        # Handle 'endpoint' starts - certainly acyclic
        n = len(paths)
        for node, degree in G.out_degree().items():
            if degree == 1:
                # Start traveling
                paths.append(find_path(G, node))
        G.remove_nodes_from(nx.isolates(G))
        if n == len(paths):
            # No change since last pass = exhausted attempts
            break
    return paths


def process_cyclic(graph):
    paths = []
    while True:
        # Pick the next edge (or random - there's no strategy here)
        try:
            edge = graph.edges_iter().next()
        except StopIteration:
            break
        # Start traveling
        node = edge[0]
        paths.append(find_path(graph, node))
    return paths


def find_path(graph, node):
    '''Given a starting node, travel until one of the following conditions is
    met:
    1) The path terminates (node degree 1)
    2) A node has been revisited (cycle)

    '''
    path = []

    def ccw_dist(az1, az2):
        # az1 is azimuth of interest, az2 is for comparison. The vectors az1
        # and az2 are connected - az2 begins where az1 ends. Therefore, if az1
        # is 0, an az2 that's likely to be closest in counterclockwise
        # direction will be slightly smaller than pi
        # For the returned value, a smaller value = closer in the
        # counterclockwise direction
        diff = (az1 + np.pi) % (2 * np.pi) - az2
        if diff < 0:
            diff += 2 * np.pi
        return diff

    # Travel the first edge
    next_node, edge_attr = graph[node].items()[0]
    path.append(edge_attr)
    graph.remove_edge(node, next_node)
    while True:
        # Choose the next edge - the nearest clockwise edge
        az = edge_attr['azimuth']
        if graph.out_degree(next_node) == 1:
            # This is a terminal node for our purposes - we're reversing course
            # and would revisit the previous node.
            break
        edges_out = graph[next_node].items()
        # Don't retravel previous edge
        edges_out = [e for e in edges_out if e[0] != node]
        if not edges_out:
            # Terminal node reached
            break
        node = next_node

        next_node, edge_attr = min(edges_out,
                                   key=lambda x: ccw_dist(az, x[1]['azimuth']))
        if edge_attr in path:
            # We've visited this edge before - cycle reached
            break
        path.append(edge_attr)
        graph.remove_edge(node, next_node)

    return path


def path_to_geom(path):
    coords = []
    coords.append(path[0]['geometry'].coords[0])
    for p in path:
        coords += p['geometry'].coords[1:]
    return geometry.LineString(coords)


def graph_workflow(path):
    orig = gpd.read_file(path)
    graph = create_graph(path)
    acyclic_paths = process_acyclic(graph)
    cyclic_paths = process_cyclic(graph)
    paths = []
    for i, p in enumerate(acyclic_paths + cyclic_paths):
        datalist = []
        for edge in p:
            orig_row = orig.loc[orig['id'] == edge['id']]
            if edge['forward']:
                sidewalk = orig_row.iloc[0]['sw_right']
            else:
                sidewalk = orig_row.iloc[0]['sw_left']
            datalist.append({
                'geometry': edge['geometry'],
                'sidewalk': sidewalk
            })
        paths.append(datalist)

    return paths
