#!/bin/bash 
# Combine vector data in mbtiles format

# Inserts all tiles from [source] into [dest], replacing any old tiles
# in [dest].

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

CWD=$(pwd)
SOURCEDIR=$CWD
case $1 in
   "-d" | "--dir")
      SOURCEDIR=$2
      cd $SOURCEDIR
      shift 2
      ;;
esac
SOURCE=$1
DEST=$2
if [ -z "$SOURCE" ] || [ -z "$DEST" ]; then
    echo "usage: append2region [directory containing source mbtiles] [dest]" 
    exit 1
fi

if [ ! -f $SOURCE ] && [ ! -d $SOURCE ]; then
    echo "File/directory '$SOURCE' does not exist."
    exit 1
fi

# The function of this script that actually does what's wanted
append_data(){
   echo "
   PRAGMA journal_mode=PERSIST;
   PRAGMA page_size=80000;
   PRAGMA synchronous=OFF;
   ATTACH DATABASE '$1' AS source;
   REPLACE INTO map SELECT * FROM source.map WHERE source.map.zoom_level <= 4;
   REPLACE INTO main.images SELECT * FROM source.images where source.images.tile_id in (select tile_id from main.map);"\
   | sqlite3 $DEST
}
# is the output filename full path?
LEADER=${DEST:0:1}
if [ "$LEADER" != "/" ];then
   mkdir -p output
   DEST=$SOURCEDIR/output/$DEST
fi

echo "Destination: $DEST"

if [ "$DEST" == "$SOURCEDIR/output/." ]; then
   DEST=$SOURCEDIR/output/combined_regions.sqlite
fi
   
# does the target mbtile already exist? Create if not
if [ ! -f $DEST ]; then
# create the empty database
   echo ".q" | sqlite3 $DEST
   # provide the structure
   echo "
   CREATE TABLE images (tile_id TEXT, tile_data BLOB);
   CREATE TABLE map (zoom_level INTEGER,tile_column INTEGER,tile_row INTEGER,tile_id TEXT,grid_id TEXT);
   CREATE TABLE metadata (name TEXT, value TEXT);
   CREATE TABLE gpkg_spatial_ref_sys (
       srs_name TEXT NOT NULL,  srs_id INTEGER NOT NULL PRIMARY KEY,
       organization TEXT NOT NULL, organization_coordsys_id INTEGER NOT NULL,
       definition  TEXT NOT NULL, description TEXT);
   CREATE TABLE gpkg_contents (
       table_name TEXT NOT NULL PRIMARY KEY, data_type TEXT NOT NULL,
       identifier TEXT UNIQUE, description TEXT DEFAULT '',
       last_change DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', CURRENT_TIMESTAMP)),
       min_x DOUBLE, min_y DOUBLE, max_x DOUBLE, max_y DOUBLE, srs_id INTEGER,
       CONSTRAINT fk_gc_r_srs_id FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id));
   CREATE TABLE gpkg_geometry_columns (
       table_name TEXT NOT NULL, column_name TEXT NOT NULL, geometry_type_name TEXT NOT NULL,
       srs_id INTEGER NOT NULL, z TINYINT NOT NULL, m TINYINT NOT NULL,
       CONSTRAINT pk_geom_cols PRIMARY KEY (table_name, column_name),
       CONSTRAINT uk_gc_table_name UNIQUE (table_name),
       CONSTRAINT fk_gc_tn FOREIGN KEY (table_name) REFERENCES gpkg_contents(table_name),
       CONSTRAINT fk_gc_srs FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys (srs_id));
   CREATE TABLE gpkg_tile_matrix_set (
       table_name TEXT NOT NULL PRIMARY KEY, srs_id INTEGER NOT NULL,
       min_x DOUBLE NOT NULL, min_y DOUBLE NOT NULL, max_x DOUBLE NOT NULL, max_y DOUBLE NOT NULL,
       CONSTRAINT fk_gtms_table_name FOREIGN KEY (table_name) REFERENCES gpkg_contents(table_name),
       CONSTRAINT fk_gtms_srs FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys (srs_id));
   CREATE TABLE gpkg_tile_matrix (
       table_name TEXT NOT NULL, zoom_level INTEGER NOT NULL,
       matrix_width INTEGER NOT NULL, matrix_height INTEGER NOT NULL,
       tile_width INTEGER NOT NULL, tile_height INTEGER NOT NULL,
       pixel_x_size DOUBLE NOT NULL, pixel_y_size DOUBLE NOT NULL,
       CONSTRAINT pk_ttm PRIMARY KEY (table_name, zoom_level),
       CONSTRAINT fk_tmm_table_name FOREIGN KEY (table_name) REFERENCES gpkg_contents(table_name));
   CREATE TABLE gpkg_metadata (
       id INTEGER CONSTRAINT m_pk PRIMARY KEY ASC NOT NULL UNIQUE,
       md_scope TEXT NOT NULL DEFAULT 'dataset', md_standard_uri TEXT NOT NULL,
       mime_type TEXT NOT NULL DEFAULT 'text/xml',metadata TEXT NOT NULL);
   CREATE TABLE gpkg_metadata_reference (
       reference_scope TEXT NOT NULL,table_name TEXT,column_name TEXT,row_id_value INTEGER,
       timestamp DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ',CURRENT_TIMESTAMP)),
       md_file_id INTEGER NOT NULL,md_parent_id INTEGER,
       CONSTRAINT crmr_mfi_fk FOREIGN KEY (md_file_id) REFERENCES gpkg_metadata(id),
       CONSTRAINT crmr_mpi_fk FOREIGN KEY (md_parent_id) REFERENCES gpkg_metadata(id));
   CREATE UNIQUE INDEX map_index ON map (zoom_level,tile_column,tile_row);
   CREATE UNIQUE INDEX images_index ON images (tile_id);
   CREATE VIEW tiles AS   SELECT map.zoom_level as zoom_level,    map.tile_column as tile_column,    map.tile_row as tile_row,    images.tile_data as tile_data   FROM map JOIN images ON map.tile_id = images.tile_id;
   CREATE VIEW package_tiles AS
     SELECT map.rowid as id,
       map.zoom_level as zoom_level,
       map.tile_column as tile_column,
       ((1 << map.zoom_level) - map.tile_row - 1) as tile_row,
       images.tile_data as tile_data
     FROM map JOIN images ON map.tile_id = images.tile_id;
   CREATE TABLE omtm (name TEXT, value TEXT);"| \
   sqlite3 $DEST
fi

if [ -f $SOURCE ];then
   echo "append2region $SOURCE => $DEST ..."
   append_data $SOURCE
else
   mbtfile=`ls $SOURCEDIR/*.mbtiles 2>/dev/null | head -n1`
   if [ -z "$mbtfile" ];then
      echo "no mbtiles found"
      exit 1
   fi
   for f in `ls $SOURCEDIR/*.mbtiles`;do
      echo "append2region $f => $DEST ..."
      append_data $f
   done
fi
# the vacuum command will collapse out any garbage space
sqlite3 $DEST "vacuum;"

# all done return to original directory
cd $CWD
