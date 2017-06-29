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

	log "github.com/Sirupsen/logrus"
)

type MetricsCheck struct {
}

// We lay out two format strings so we can align both the title and the
// lines of the report to try and make it 'tabulised'
//                        P/F: Name: Min   < Mean  < Max:  Iter: SD:   CoV %"
var TitleFormat string = "%4s: %20s: %7s < %7s < %7s: %5s: %7s: %7s %% "
var LineFormat string = "%4s: %20s: %7.2f < %7.2f < %7.2f: %5d: %7.2f: %7.2f %% "

func (mc MetricsCheck) ReportTitle() (string) {
	return fmt.Sprintf(TitleFormat,
		"P/F",
		"Name",
		"Min",
		"Mean",
		"Max",
		"Iters",
		"SD",
		"CoV" )
}

func (mc *MetricsCheck) Check(m Metric, c Csv) (err error, summary string) {
	var pass bool = true
	var passtring string

	log.Debugf("Compare check for [%s]", m.Name)


	log.Debugf(" Check MinVal (%f > %f)", m.MinVal, c.Mean)
	if c.Mean < m.MinVal {
		log.Warnf("Failed Minval (%7f > %7f) for [%s]",
			m.MinVal, c.Mean,
			m.Name)
		pass = false
	} else {
		log.Debug("Passed")
	}

	log.Debugf(" Check MaxVal (%f < %f)", m.MaxVal, c.Mean)
	if c.Mean > m.MaxVal {
		log.Warnf("Failed Maxval (%7f < %7f) for [%s]",
			m.MaxVal, c.Mean,
			m.Name)
		pass = false
	} else {
		log.Debug("Passed")
	}

	if pass == true {
		passtring = "Pass"
	} else {
		passtring = "Fail"
		err = errors.New("Failed")
	}

	summary += fmt.Sprintf(LineFormat,
		passtring,
		m.Name,
		m.MinVal, c.Mean, m.MaxVal,
		c.Iterations,
		c.SD, c.CoV)

	return
}
