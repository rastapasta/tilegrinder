# tilegrinder
[![npm version](https://badge.fury.io/js/tilegrinder.svg)](https://badge.fury.io/js/tilegrinder)
![dependencies](https://david-dm.org/rastapasta/tilegrinder.svg)
![license](https://img.shields.io/github/license/rastapasta/tilegrinder.svg)

A handy library in case you ever want to apply some logic to all/some [vector tiles](https://github.com/mapbox/vector-tile-spec/tree/master/2.1) in an [MBTiles](https://www.mapbox.com/help/an-open-platform/#mbtiles) file without having to worry about how to pull, decode, alter, encode and store them again.

It's pretty simple: you define a source and a destination - and a callback which gets called with a deserialized tile object as soon as the async grinder parsed another tile. The library transparently takes care of compression, protobuf and geometry de-/encoding and rebundling of the altered data into a new MBTiles.

Take a look at [`tileshrink`](https://github.com/rastapasta/tileshrink) to see what you can build with it!

## Requirements

* `tilegrinder` uses the native protobuf wrapper library [`node-protobuf`](https://github.com/fuwaneko/node-protobuf) for its magic

* To let it build during `npm install`, take care of following things:

  * Linux: `libprotobuf` must be present (`apt-get install build-essential pkg-config libprotobuf-dev`)

  * OSX: Use [`homebrew`](http://brew.sh/) to install `protobuf` with `brew install pkg-config protobuf`

  * Windows: `node-protobuf` includes a pre-compiled version for 64bit systems

## How to install it?

* Just install it into your project folder with

    `npm install --save tilegrinder`

## How to code it?

Following example will

* create a new MBTiles file `simple.mbtiles` containing the tiles of the first 4 zoom levels of  `planet.mbtiles`

* only the `water`, `admin` and `road` layers are kept

* while all points get moved by an offset of 256

```js
"use strict";
const TileGrinder = require('tilegrinder');

let grinder = new TileGrinder({maxZoom: 4});

grinder.grind("planet.mbtiles", "simple.mbtiles", tile => {

  // Only keep the road, water and admin layers
  tile.layers = tile.layers.filter(layer =>
    layer.name === "water" || layer.name === "admin" || layer.name === "road"
  );

  // Move each point a bit around
  tile.layers.forEach(layer => {
    layer.features.forEach(feature => {
      feature.geometry.forEach(geometry => {
        geometry.forEach(point => {
          point.x += 256;
          point.y += 256;
        });
      });
    })
  });

});
```

Which will generate following output:

```bash
bash$ node example.js
[>] starting to grind
[>] 38% less data in zoom 1, x: 0 y: 1
[>] 39% less data in zoom 1, x: 1 y: 1
[>] 20% less data in zoom 1, x: 0 y: 0
.......
[>] 16% less data in zoom 2, x: 2 y: 1
[>] 33% less data in zoom 4, x: 8 y: 5
[+] waiting for workers to finish...
[+] finishing database
[+] grinding done!
[>] saved 35% of storage
bash$
```

## License
#### The MIT License (MIT)
Copyright (c) 2016 Michael Straßburger

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
