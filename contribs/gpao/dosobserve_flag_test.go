package main

import "flag"

var observeFlag bool

func init() { flag.BoolVar(&observeFlag, "observe", false, "run the halt observation demo") }
