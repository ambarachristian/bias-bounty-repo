INSTALL httpfs; LOAD httpfs;
INSTALL spatial; LOAD spatial;
SET s3_region='us-west-2';
SET s3_url_style='path';
SET memory_limit='1500MB';
SET temp_directory='tmp/spill';
SET preserve_insertion_order=false;
SET threads=4;
