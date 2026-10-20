// PKGPATH: gno.land/r/example
package example

import (
	"gno.land/p/archive/dom"
)

var gPlot *dom.Plot

func init() {
	gPlot = &dom.Plot{Name: "First Plot"}
}

func main(cur realm) {
	gPlot.AddPost("TEST_TITLE", "TEST_BODY")
	println(gPlot.String())
}

// Output:
// # [plot] First Plot
//
// ## TEST_TITLE
// TEST_BODY

// Realm:
// finalizerealm["gno.land/r/example"]
// c[0ffd45e074aa1b8df562907c95ad97526b7ca187:14](257)={
//     "Fields": [
//         {
//             "T": {
//                 "@type": "/gno.PointerType",
//                 "Elt": {
//                     "@type": "/gno.RefType",
//                     "ID": "gno.land/p/nt/avl/v0.Node"
//                 }
//             }
//         }
//     ],
//     "ObjectInfo": {
//         "ID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:14",
//         "LastObjectSize": "257",
//         "ModTime": "0",
//         "OwnerID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:13",
//         "RefCount": "1"
//     }
// }
// c[0ffd45e074aa1b8df562907c95ad97526b7ca187:13](485)={
//     "Fields": [
//         {
//             "T": {
//                 "@type": "/gno.PrimitiveType",
//                 "value": "16"
//             },
//             "V": {
//                 "@type": "/gno.StringValue",
//                 "value": "TEST_TITLE"
//             }
//         },
//         {
//             "T": {
//                 "@type": "/gno.PrimitiveType",
//                 "value": "16"
//             },
//             "V": {
//                 "@type": "/gno.StringValue",
//                 "value": "TEST_BODY"
//             }
//         },
//         {
//             "T": {
//                 "@type": "/gno.RefType",
//                 "ID": "gno.land/p/nt/avl/v0.Tree"
//             },
//             "V": {
//                 "@type": "/gno.RefValue",
//                 "Hash": "f29452900c9e9bf5475fd7e589f1bd8714958f3d",
//                 "ObjectID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:14"
//             }
//         }
//     ],
//     "ObjectInfo": {
//         "ID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:13",
//         "LastObjectSize": "485",
//         "ModTime": "0",
//         "OwnerID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:12",
//         "RefCount": "1"
//     }
// }
// c[0ffd45e074aa1b8df562907c95ad97526b7ca187:12](346)={
//     "ObjectInfo": {
//         "ID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:12",
//         "LastObjectSize": "346",
//         "ModTime": "0",
//         "OwnerID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:11",
//         "RefCount": "1"
//     },
//     "Value": {
//         "T": {
//             "@type": "/gno.RefType",
//             "ID": "gno.land/p/archive/dom.Post"
//         },
//         "V": {
//             "@type": "/gno.RefValue",
//             "Hash": "187c2d3f28c73395ee97bf19409147e94389ff96",
//             "ObjectID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:13"
//         }
//     }
// }
// c[0ffd45e074aa1b8df562907c95ad97526b7ca187:11](687)={
//     "Fields": [
//         {
//             "T": {
//                 "@type": "/gno.PrimitiveType",
//                 "value": "16"
//             },
//             "V": {
//                 "@type": "/gno.StringValue",
//                 "value": "0"
//             }
//         },
//         {
//             "T": {
//                 "@type": "/gno.PointerType",
//                 "Elt": {
//                     "@type": "/gno.RefType",
//                     "ID": "gno.land/p/archive/dom.Post"
//                 }
//             },
//             "V": {
//                 "@type": "/gno.PointerValue",
//                 "Base": {
//                     "@type": "/gno.RefValue",
//                     "Hash": "82b9b0210cb8614983737976800b64daad781994",
//                     "ObjectID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:12"
//                 },
//                 "Index": "0",
//                 "TV": null
//             }
//         },
//         {
//             "T": {
//                 "@type": "/gno.PrimitiveType",
//                 "value": "64"
//             }
//         },
//         {
//             "N": "AQAAAAAAAAA=",
//             "T": {
//                 "@type": "/gno.PrimitiveType",
//                 "value": "32"
//             }
//         },
//         {
//             "T": {
//                 "@type": "/gno.PointerType",
//                 "Elt": {
//                     "@type": "/gno.RefType",
//                     "ID": "gno.land/p/nt/avl/v0.Node"
//                 }
//             }
//         },
//         {
//             "T": {
//                 "@type": "/gno.PointerType",
//                 "Elt": {
//                     "@type": "/gno.RefType",
//                     "ID": "gno.land/p/nt/avl/v0.Node"
//                 }
//             }
//         }
//     ],
//     "ObjectInfo": {
//         "ID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:11",
//         "LastObjectSize": "687",
//         "ModTime": "0",
//         "OwnerID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:10",
//         "RefCount": "1"
//     }
// }
// c[0ffd45e074aa1b8df562907c95ad97526b7ca187:10](343)={
//     "ObjectInfo": {
//         "ID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:10",
//         "LastObjectSize": "343",
//         "ModTime": "0",
//         "OwnerID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:9",
//         "RefCount": "1"
//     },
//     "Value": {
//         "T": {
//             "@type": "/gno.RefType",
//             "ID": "gno.land/p/nt/avl/v0.Node"
//         },
//         "V": {
//             "@type": "/gno.RefValue",
//             "Hash": "ac7d986ec6e1ed131a9838b1258062756c7c4078",
//             "ObjectID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:11"
//         }
//     }
// }
// u[0ffd45e074aa1b8df562907c95ad97526b7ca187:9](135)=
//     @@ -7,13 +7,23 @@
//                          "@type": "/gno.RefType",
//                          "ID": "gno.land/p/nt/avl/v0.Node"
//                      }
//     +            },
//     +            "V": {
//     +                "@type": "/gno.PointerValue",
//     +                "Base": {
//     +                    "@type": "/gno.RefValue",
//     +                    "Hash": "0f72acf6f18bb025291bdefef9706e3917b96972",
//     +                    "ObjectID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:10"
//     +                },
//     +                "Index": "0",
//     +                "TV": null
//                  }
//              }
//          ],
//          "ObjectInfo": {
//              "ID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:9",
//              "LastObjectSize": "255",
//     -        "ModTime": "0",
//     +        "ModTime": "9",
//              "OwnerID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:8",
//              "RefCount": "1"
//          }
// u[0ffd45e074aa1b8df562907c95ad97526b7ca187:8](5)=
//     @@ -17,11 +17,12 @@
//                  },
//                  "V": {
//                      "@type": "/gno.RefValue",
//     -                "Hash": "0f0e314e82aa24001576643128a2ca8c88a694bc",
//     +                "Hash": "0ba71e88b7f0194079c96901059b90d2970d0974",
//                      "ObjectID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:9"
//                  }
//              },
//              {
//     +            "N": "AQAAAAAAAAA=",
//                  "T": {
//                      "@type": "/gno.PrimitiveType",
//                      "value": "32"
//     @@ -31,7 +32,7 @@
//          "ObjectInfo": {
//              "ID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:8",
//              "LastObjectSize": "449",
//     -        "ModTime": "0",
//     +        "ModTime": "9",
//              "OwnerID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:7",
//              "RefCount": "1"
//          }
// u[0ffd45e074aa1b8df562907c95ad97526b7ca187:7](5)=
//     @@ -2,7 +2,7 @@
//          "ObjectInfo": {
//              "ID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:7",
//              "LastObjectSize": "343",
//     -        "ModTime": "0",
//     +        "ModTime": "14",
//              "OwnerID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:3",
//              "RefCount": "1"
//          },
//     @@ -13,7 +13,7 @@
//              },
//              "V": {
//                  "@type": "/gno.RefValue",
//     -            "Hash": "e6fac8453db0e001e9133bcf81262b373ff4b890",
//     +            "Hash": "e85dacc8386d15658264e5fef9c92fe23bb71338",
//                  "ObjectID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:8"
//              }
//          }
// u[0ffd45e074aa1b8df562907c95ad97526b7ca187:3](0)=
//     @@ -2,7 +2,7 @@
//          "ObjectInfo": {
//              "ID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:3",
//              "LastObjectSize": "393",
//     -        "ModTime": "6",
//     +        "ModTime": "14",
//              "OwnerID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:2",
//              "RefCount": "1"
//          },
//     @@ -18,7 +18,7 @@
//                  "@type": "/gno.PointerValue",
//                  "Base": {
//                      "@type": "/gno.RefValue",
//     -                "Hash": "9a4ec331d26d00af41906d001c42ab34bba8ebce",
//     +                "Hash": "8a48aaba4d0b97f8cfeb378e09ccdaabf201bd0b",
//                      "ObjectID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:7"
//                  },
//                  "Index": "0",
// u[0ffd45e074aa1b8df562907c95ad97526b7ca187:2](0)=
//     @@ -4,7 +4,7 @@
//              "ID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:2",
//              "IsEscaped": true,
//              "LastObjectSize": "680",
//     -        "ModTime": "9",
//     +        "ModTime": "14",
//              "RefCount": "2"
//          },
//          "Parent": null,
//     @@ -34,7 +34,7 @@
//                  },
//                  "V": {
//                      "@type": "/gno.RefValue",
//     -                "Hash": "746894b063dbecdefc71e7c1b7f2aa6d76377048",
//     +                "Hash": "238c2abbc2cd0ee898c106f6938afd7ac4bdabdb",
//                      "ObjectID": "0ffd45e074aa1b8df562907c95ad97526b7ca187:3"
//                  }
//              },
