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

	log "github.com/Sirupsen/logrus"
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
	var finalerror error // If we fail any metric, fail globally
	var report []string  // summary report table
	var passes int
	var fails int

	log.Debug("processMetrics")

	for _, m := range ciBasefile.Metric {
		var thisCsv Csv

		log.Debugf("Processing %s", m.Name)
		fullpath := path.Join(context.GlobalString("metricsdir"), m.Name)
		fullpath = fullpath + ".csv"

		log.Debugf("Fullpath %s", fullpath)
		err = thisCsv.load(fullpath)
		if err != nil {
			log.Warnf("Failed to open csv [%s]", fullpath)
			return err
		}

		// Now we have both the baseline and the CSV data loaded,
		// let's go compare them
		var mc MetricsCheck

		err, summary := mc.Check(m, thisCsv)
		if err != nil {
			log.Warnf("Check for [%s] failed", m.Name)
			log.Warnf(" with [%s]", summary)
			finalerror = errors.New("Fail")
			fails += 1
		} else {
			log.Debugf("Check for [%s] passed", m.Name)
			log.Debugf(" with [%s]", summary)
			passes += 1
		}

		report = append(report, summary)

		log.Debugf("Done %s", m.Name)
	}

	if finalerror != nil {
		log.Warn("Overall we failed")
	}

	// Note - not logging here - the summary goes to stdout
	fmt.Println("\nReport Summary:")

	var mc MetricsCheck
	fmt.Println(mc.ReportTitle())
	for _, s := range report {
		fmt.Println(s)
	}
	fmt.Printf("Fails: %d, Passes %d\n", fails, passes)

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
			Name:  "basefile",
			Usage: "path to baseline TOML metrics file",
		},
		cli.BoolFlag{
			Name:  "debug",
			Usage: "enable debug output in the log",
		},
		cli.StringFlag{
			Name: "log",
			//Value: "/dev/null",
			Usage: "set the log file path",
		},
		cli.StringFlag{
			Name:  "metricsdir",
			Usage: "directory container CSV metrics",
		},
	}

	app.Before = func(context *cli.Context) error {
		var err error

		if path := context.GlobalString("log"); path != "" {
			f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND|os.O_SYNC, 0640)
			if err != nil {
				return err
			}
			log.SetOutput(f)
		}

		if context.GlobalBool("debug") {
			log.SetLevel(log.DebugLevel)
		}

		ciBasefile, err = NewBasefile(context.GlobalString("basefile"))
		if err != nil {
			return err
		}

		return nil
	}

	app.Action = func(context *cli.Context) error {
		return processMetrics(context)
	}

	if err := app.Run(os.Args); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
