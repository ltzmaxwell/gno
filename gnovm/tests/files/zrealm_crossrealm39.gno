// PKGPATH: gno.land/r/crossrealm
package crossrealm

import (
	"gno.land/r/tests/vm/crossrealm_b"
)

type S struct {
	v *int
}

var v S

// A dirties v (its StructValue) and creates v.v, then B stores &v: v
// escapes, and B finalizes first with v dirty under B. B hands v to its
// owner A, which saves v.v (new id) and the StructValue before v, so v's
// RefValue to the StructValue carries its hash. The ops log pins that
// order: B writes only its own objects (:13, :2), then A writes :7, :4, :3.
func main(cur realm) {
	v.v = new(int)
	crossrealm_b.SetObject(cross(cur), &v)
	*v.v = 7
	println("done")
}

// Output:
// done

// Realm:
// finalizerealm["gno.land/r/tests/vm/crossrealm_b"]
// u[06279d1e03ecb38b84822f9caf584bd16913470d:13](199)=
//     @@ -2,9 +2,26 @@
//          "ObjectInfo": {
//              "ID": "06279d1e03ecb38b84822f9caf584bd16913470d:13",
//              "LastObjectSize": "191",
//     -        "ModTime": "0",
//     +        "ModTime": "20",
//              "OwnerID": "06279d1e03ecb38b84822f9caf584bd16913470d:2",
//              "RefCount": "1"
//          },
//     -    "Value": {}
//     +    "Value": {
//     +        "T": {
//     +            "@type": "/gno.PointerType",
//     +            "Elt": {
//     +                "@type": "/gno.RefType",
//     +                "ID": "gno.land/r/crossrealm.S"
//     +            }
//     +        },
//     +        "V": {
//     +            "@type": "/gno.PointerValue",
//     +            "Base": {
//     +                "@type": "/gno.RefValue",
//     +                "ObjectID": "0c8307f7bbe97fdb07b2d0fa6907b8d67517c02a:3"
//     +            },
//     +            "Index": "0",
//     +            "TV": null
//     +        }
//     +    }
//      }
// u[06279d1e03ecb38b84822f9caf584bd16913470d:2](5)=
//     @@ -4,7 +4,7 @@
//              "ID": "06279d1e03ecb38b84822f9caf584bd16913470d:2",
//              "IsEscaped": true,
//              "LastObjectSize": "2495",
//     -        "ModTime": "0",
//     +        "ModTime": "20",
//              "RefCount": "2"
//          },
//          "Parent": null,
//     @@ -120,7 +120,7 @@
//                  },
//                  "V": {
//                      "@type": "/gno.RefValue",
//     -                "Hash": "1a1bad0b9e9c1282896dc99ce4e5ba6255cc3444",
//     +                "Hash": "eda7c12554e0497084686982d307a187dc5a91d0",
//                      "ObjectID": "06279d1e03ecb38b84822f9caf584bd16913470d:13"
//                  }
//              },
// finalizerealm["gno.land/r/crossrealm"]
// c[0c8307f7bbe97fdb07b2d0fa6907b8d67517c02a:7](216)={
//     "ObjectInfo": {
//         "ID": "0c8307f7bbe97fdb07b2d0fa6907b8d67517c02a:7",
//         "LastObjectSize": "216",
//         "ModTime": "0",
//         "OwnerID": "0c8307f7bbe97fdb07b2d0fa6907b8d67517c02a:4",
//         "RefCount": "1"
//     },
//     "Value": {
//         "N": "BwAAAAAAAAA=",
//         "T": {
//             "@type": "/gno.PrimitiveType",
//             "value": "32"
//         }
//     }
// }
// u[0c8307f7bbe97fdb07b2d0fa6907b8d67517c02a:4](134)=
//     @@ -7,13 +7,23 @@
//                          "@type": "/gno.PrimitiveType",
//                          "value": "32"
//                      }
//     +            },
//     +            "V": {
//     +                "@type": "/gno.PointerValue",
//     +                "Base": {
//     +                    "@type": "/gno.RefValue",
//     +                    "Hash": "5b3025334888e6a8cb17ef1768ab778ebfc2040e",
//     +                    "ObjectID": "0c8307f7bbe97fdb07b2d0fa6907b8d67517c02a:7"
//     +                },
//     +                "Index": "0",
//     +                "TV": null
//                  }
//              }
//          ],
//          "ObjectInfo": {
//              "ID": "0c8307f7bbe97fdb07b2d0fa6907b8d67517c02a:4",
//              "LastObjectSize": "236",
//     -        "ModTime": "0",
//     +        "ModTime": "6",
//              "OwnerID": "0c8307f7bbe97fdb07b2d0fa6907b8d67517c02a:3",
//              "RefCount": "1"
//          }
// u[0c8307f7bbe97fdb07b2d0fa6907b8d67517c02a:3](7)=
//     @@ -1,10 +1,10 @@
//      {
//          "ObjectInfo": {
//              "ID": "0c8307f7bbe97fdb07b2d0fa6907b8d67517c02a:3",
//     +        "IsEscaped": true,
//              "LastObjectSize": "339",
//     -        "ModTime": "0",
//     -        "OwnerID": "0c8307f7bbe97fdb07b2d0fa6907b8d67517c02a:2",
//     -        "RefCount": "1"
//     +        "ModTime": "20",
//     +        "RefCount": "2"
//          },
//          "Value": {
//              "T": {
//     @@ -13,7 +13,7 @@
//              },
//              "V": {
//                  "@type": "/gno.RefValue",
//     -            "Hash": "8a904c6359ef192933c0b1dc467b39d2e0ae1d01",
//     +            "Hash": "7968cb585c1cd0a4a29a8187fd4063b1947cfe6c",
//                  "ObjectID": "0c8307f7bbe97fdb07b2d0fa6907b8d67517c02a:4"
//              }
//          }
// u[0c8307f7bbe97fdb07b2d0fa6907b8d67517c02a:2](5)=
//     @@ -4,7 +4,7 @@
//              "ID": "0c8307f7bbe97fdb07b2d0fa6907b8d67517c02a:2",
//              "IsEscaped": true,
//              "LastObjectSize": "635",
//     -        "ModTime": "0",
//     +        "ModTime": "20",
//              "RefCount": "2"
//          },
//          "Parent": null,
//     @@ -46,7 +46,6 @@
//                  },
//                  "V": {
//                      "@type": "/gno.RefValue",
//     -                "Hash": "808e3fc81211a0f25d2ae6a7338044e0092e7b98",
//                      "ObjectID": "0c8307f7bbe97fdb07b2d0fa6907b8d67517c02a:3"
//                  }
//              },
