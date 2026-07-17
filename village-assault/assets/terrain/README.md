# Terrain Tiles

`terrain_tiles.png` is the runtime atlas. It contains four 16 x 16 variants per
material, arranged as four columns by ten rows:

1. Brown topsoil
2. Grass over topsoil
3. Dark cave/background soil
4. Light loam
5. Deep umber soil
6. Red clay
7. Tan silt
8. Stone mixed with soil
9. Mossy grass over deep soil
10. Transparent gold-fleck overlay

`terrain_tiles_source.png` is the high-resolution 5 x 2 source sheet used for the
runtime atlas's palette and material direction. The runtime tiles were then curated at
their native resolution to keep their pixels crisp and remove repeating diagonal
patterns. Keep the row order and 16 x 16 tile size stable when replacing the runtime
art; terrain code selects materials by row and visual variants by column.

The source sheet was created with the built-in image generation tool using this art
direction: an original 16-bit side-view sandbox terrain tileset with irregular pixel
clusters, pebbles, roots, granular soil, restrained natural colors, seamless edges,
and no brick or mortar patterns.
