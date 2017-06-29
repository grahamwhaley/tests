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
	"fmt"
	"io/ioutil"

	"github.com/BurntSushi/toml"
	log "github.com/Sirupsen/logrus"
)

// Config represents the configuration file
type Basefile struct {
	Metric []Metric
}

// NewConfig load the configuration file in a Config object
// and returns it
func NewBasefile(file string) (*Basefile, error) {
	if file == "" {
		log.Error("Missing basefile argument")
		return nil, fmt.Errorf("missing baseline reference file")
	}

	configuration, err := ioutil.ReadFile(file)
	if err != nil {
		return nil, err
	}

	var basefile Basefile
	if err := toml.Unmarshal(configuration, &basefile); err != nil {
		return nil, err
	}

	return &basefile, nil
}
