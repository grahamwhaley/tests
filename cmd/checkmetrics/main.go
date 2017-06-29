// Copyright (c) 2017 Intel Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"errors"
	"fmt"
	"os"
	"path"

	"github.com/urfave/cli"
)

// version is the version of the program. It is specified at compilation time
const version = ""

// commit is the git commit of the program. It is specified at compilation time
const commit = ""

// name is the name of the program.
const name = "checkmetrics"

// usage is the usage of the program.
const usage = name + ` checks CSV metrics results against a TOML baseline`

var ciBasefile *Basefile

func processMetrics(context *cli.Context) error {
	var err error
	var finalerror error	// If we fail any metric, fail globally
	var report []string	// summary report table

	fmt.Println("in processMetrics")

	for _, m := range ciBasefile.Metric {
		var thisCsv Csv

		fmt.Printf("Processing %s\n", m.Name)
		fullpath := path.Join(context.GlobalString("metricsdir"), m.Name)
		fullpath = fullpath + ".csv"

		fmt.Printf("Fullpath %s\n", fullpath)
		err = thisCsv.load(fullpath)
		if err != nil {
			fmt.Println("Failed to open csv")
			return err
		}

		// Now we have both the baseline and the CSV data loaded,
		// let's go compare them
		var  mc MetricsCheck

		err, summary := mc.Check(m, thisCsv)
		if err != nil {
			fmt.Printf("Check for [%s] failed\n", m.Name)
			fmt.Printf(" with [%s]\n", summary)
			finalerror = errors.New("Fail")
		} else {
			fmt.Printf("Check for [%s] passed\n", m.Name)
			fmt.Printf(" with [%s]\n", summary)
		}

		report = append(report, summary)

		fmt.Printf("Done %s\n", m.Name)
	}

	if finalerror != nil {
		fmt.Println("Overall we failed")
	}

	fmt.Println("Report Summary:")
	for _, s := range report {
		fmt.Println(s)
	}

	return finalerror
}

func main() {
	app := cli.NewApp()
	app.Name = name
	app.Usage = usage
	app.Version = version

	// Override the default function to display version details to
	// ensure the "--version" option and "version" command are identical.
	cli.VersionPrinter = func(c *cli.Context) {
		fmt.Println(c.App.Version)
	}

	app.Flags = []cli.Flag{
		cli.StringFlag{
			Name:  "metricsdir",
			Usage: "directory container CSV metrics",
		},
		cli.StringFlag{
			Name:  "basefile",
			Usage: "path to baseline TOML metrics file",
		},
	}

	app.Before = func(context *cli.Context) error {
		var err error

		ciBasefile, err = NewBasefile(context.GlobalString("basefile"))
		if err != nil {
			return err
		}

		return nil
	}

	app.Action = func(context *cli.Context) error {
		fmt.Println("in Action")
		processMetrics(context)

		return nil
	}

	if err := app.Run(os.Args); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
