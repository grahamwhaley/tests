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
)

type MetricsCheck struct {
	summaryLayout string
}

func (mc *MetricsCheck) Check(m Metric, c Csv) (err error, summary string) {
	var pass bool = true

	// This is a bit skank - we really only need one of these for all
	// compare blobs
	mc.summaryLayout = "blah blah blah"

	fmt.Printf("Compare check for [%s]\n", m.Name)

	summary += m.Name + ": "
	summary += fmt.Sprintf("%f < %f < %f", m.MinVal, c.Mean, m.MaxVal)
	summary += fmt.Sprintf(" : %d", c.Iterations)

	fmt.Printf(" Check MinVal (%f < %f)\n", m.MinVal, c.Mean)
	if c.Mean < m.MinVal {
		fmt.Println("  FAIL")
		err = errors.New("MinVal")
		pass = false
	} else {
		fmt.Println("  PASS")
	}

	fmt.Printf(" Check MaxVal (%f > %f)\n", m.MaxVal, c.Mean)
	if c.Mean > m.MaxVal {
		fmt.Println("  FAIL")
		err = errors.New("MaxVal")
		pass = false
	} else {
		fmt.Println("  PASS")
	}

	if pass == true {
		summary = "Pass: " + summary
	} else {
		summary = "Fail: " + summary
	}

	return
}
