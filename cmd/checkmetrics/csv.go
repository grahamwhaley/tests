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
	"encoding/csv"
	"errors"
	"fmt"
	"os"
	"strconv"
)

// Repo represents the repository under test
type Csv struct {
	Name        string
	Records     [][]string
	ResultStrings []string		//Hold the array of all the Results as strings
	Results     []float64		//Result array converted to floats
	Iterations  int			//How many results did we gather
	Mean        float64
	MinVal      float64
	MaxVal      float64
}

func (c *Csv) load(Name string) error {
	var err error
	var f *os.File
	var r *csv.Reader

	fmt.Printf("in csv load of [%s]\n", Name)

	f, err = os.Open(Name)
	if err != nil {
		fmt.Println("Failed to open file")
		return err
	}

	defer f.Close()

	r = csv.NewReader(f)

	c.Records, _ = r.ReadAll()

	fmt.Printf(" First element is [%s]\n", c.Records[0][0] )

	if c.Records[0][4] != "Result" {
		fmt.Printf("Error, 5th column is [%s], not [Result]\n", c.Records[0][4] )
		return errors.New("Error, 5th column is not [Result]")
	}
	
	for _, r := range c.Records {
		c.ResultStrings = append(c.ResultStrings, r[4])
	}

	c.MinVal = 1000		//Do we have a NAN, MAX  or infinity we can use here?
	c.MaxVal = 0
	var total float64
	for _, r := range c.ResultStrings[1:] {
		c.Iterations += 1
		val, _ := strconv.ParseFloat(r, 64)
		c.Results = append(c.Results, val)
		total += val

		if val > c.MaxVal {
			c.MaxVal = val
		}

		if val < c.MinVal {
			c.MinVal = val
		}
	}
	c.Mean = total / float64(len(c.Records)-1)

	fmt.Printf(" Min is %f\n", c.MinVal)
	fmt.Printf(" Max is %f\n", c.MaxVal)
	fmt.Printf(" Mean is %f\n", c.Mean)

	return nil
}
