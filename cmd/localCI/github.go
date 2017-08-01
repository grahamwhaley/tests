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
	"bytes"
	"context"
	"fmt"
	"net/http"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/google/go-github/github"
	"golang.org/x/oauth2"
)

// Github represents a control version repository to
// interact with github.com
type Github struct {
	client *github.Client
	owner  string
	repo   string
	url    string
}

const (
	timeoutShortRequest = 10 * time.Second
	timeoutLongRequest  = 20 * time.Second
)

// newGithub returns an object of type Github
func newGithub(url, token string) (CVR, error) {
	url = strings.TrimSpace(url)

	ownerRepo := strings.SplitAfter(url, "/"+githubDomain+"/")

	// at least we need two tokens
	if len(ownerRepo) < 2 {
		return nil, fmt.Errorf("missing owner and repo %s", url)
	}

	ownerRepo = strings.Split(ownerRepo[1], "/")

	// at least we need two tokens: owner and repo
	if len(ownerRepo) < 2 {
		return nil, fmt.Errorf("failed to get owner and repo %s", url)
	}

	if len(ownerRepo[0]) == 0 {
		return nil, fmt.Errorf("missing owner in url %s", url)
	}

	if len(ownerRepo[1]) == 0 {
		return nil, fmt.Errorf("missing repository in url %s", url)
	}

	// create a new http client using the token
	var client *http.Client
	if token != "" {
		ts := oauth2.StaticTokenSource(
			&oauth2.Token{AccessToken: token},
		)
		client = oauth2.NewClient(context.Background(), ts)
	}

	return &Github{
		client: github.NewClient(client),
		owner:  ownerRepo[0],
		repo:   ownerRepo[1],
		url:    url,
	}, nil
}

// getDomain returns the domain name
func (g *Github) getDomain() string {
	return githubDomain
}

// getOwner returns the owner of the repo
func (g *Github) getOwner() string {
	return g.owner
}

// getRepo returns the repository name
func (g *Github) getRepo() string {
	return g.repo
}

// getOpenPullRequests returns the open pull requests
func (g *Github) getOpenPullRequests() (map[string]*PullRequest, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeoutShortRequest)
	defer cancel()

	pullRequests, _, err := g.client.PullRequests.List(ctx, g.owner, g.repo, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to list pull requests %s", err)
	}

	prs := make(map[string]*PullRequest)

	for _, pr := range pullRequests {
		if pr == nil || pr.Number == nil {
			continue
		}
		number := *pr.Number

		pullRequest, err := g.getPullRequest(number)
		if err != nil {
			continue
		}

		prs[strconv.Itoa(number)] = pullRequest
	}

	return prs, nil
}

// getPullRequest returns a specific pull request
func (g *Github) getPullRequest(pr int) (*PullRequest, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeoutShortRequest)
	defer cancel()

	// get all commits of the pull request
	listCommits, _, err := g.client.PullRequests.ListCommits(ctx, g.owner, g.repo, pr, nil)
	if err != nil {
		return nil, err
	}

	var commits []PullRequestCommit
	for _, c := range listCommits {
		if c == nil {
			return nil, fmt.Errorf("failed to get all commits of the pull request %d", pr)
		}

		if c.SHA == nil {
			return nil, fmt.Errorf("failed to get commit SHA of the pull request %d", pr)
		}
		sha := *c.SHA

		if c.Commit == nil || c.Commit.Committer == nil || c.Commit.Committer.Date == nil {
			return nil, fmt.Errorf("failed to get commit time of the pull request %d", pr)
		}
		time := *c.Commit.Committer.Date

		commits = append(commits,
			PullRequestCommit{
				Sha:  sha,
				Time: time,
			},
		)
	}

	pullRequest, _, err := g.client.PullRequests.Get(ctx, g.owner, g.repo, pr)
	if err != nil {
		return nil, err
	}

	// check the integrity of the pullRuest object before use it
	if pullRequest == nil {
		return nil, fmt.Errorf("failed to get pull request %d", pr)
	}

	if pullRequest.User == nil || pullRequest.User.Login == nil {
		return nil, fmt.Errorf("failed to get the author of the pull request %d", pr)
	}

	author := *pullRequest.User.Login

	// do not fail if we don't know if the pull request is
	// mergeable, just test it
	mergeable := true
	if pullRequest.Mergeable != nil {
		mergeable = *pullRequest.Mergeable
	}

	if pullRequest.Head == nil || pullRequest.Head.Ref == nil {
		return nil, fmt.Errorf("failed to get the branch name of the pull request %d", pr)
	}

	branchName := *pullRequest.Head.Ref

	return &PullRequest{
		Number:     pr,
		Commits:    commits,
		Author:     author,
		Mergeable:  mergeable,
		BranchName: branchName,
	}, nil
}

// getLatestPullRequestComment returns the latest comment of a specific
// user in the specific pr. If comment.User is an empty string then any user
// could be the author of the latest pull request. If comment.Comment is an empty
// string an error is returned.
func (g *Github) getLatestPullRequestComment(pr int, comment PullRequestComment) (*PullRequestComment, error) {
	if len(comment.Comment) == 0 {
		return nil, fmt.Errorf("comment cannot be an empty string")
	}

	ctx, cancel := context.WithTimeout(context.Background(), timeoutLongRequest)
	defer cancel()

	comments, _, err := g.client.Issues.ListComments(ctx, g.owner, g.repo, pr, nil)
	if err != nil {
		return nil, err
	}

	for i := len(comments) - 1; i >= 0; i-- {
		c := comments[i]
		if len(comment.User) != 0 {
			if strings.Compare(*c.User.Login, comment.User) != 0 {
				continue
			}
		}

		if strings.Compare(*c.Body, comment.Comment) == 0 {
			return &PullRequestComment{
				User:    comment.User,
				Comment: comment.Comment,
				time:    *c.CreatedAt,
			}, nil
		}
	}

	return nil, fmt.Errorf("comment '%+v' not found", comment)
}

func (g *Github) downloadPullRequest(pr int, branchName string, workingDir string) error {
	var stderr bytes.Buffer

	// clone the project
	cmd := exec.Command("git", "clone", g.url, ".")
	cmd.Dir = workingDir
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to run git clone %s %s", stderr.String(), err)
	}

	// fetch the branch
	stderr.Reset()
	cmd = exec.Command("git", "fetch", "origin", fmt.Sprintf("pull/%d/head:%s", pr, branchName))
	cmd.Dir = workingDir
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to run git fetch %s %s", stderr.String(), err)
	}

	// checkout the branch
	stderr.Reset()
	cmd = exec.Command("git", "checkout", branchName)
	cmd.Dir = workingDir
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to run git checkout %s %s", stderr.String(), err)
	}

	return nil
}

// createComment creates a comment in the specific pr
func (g *Github) createComment(pr int, comment string) error {
	ctx, cancel := context.WithTimeout(context.Background(), timeoutLongRequest)
	defer cancel()

	c := &github.IssueComment{Body: &comment}

	_, _, err := g.client.Issues.CreateComment(ctx, g.owner, g.repo, pr, c)

	return err
}

// isMember returns true if the user is member of the organization, else false
func (g *Github) isMember(user string) (bool, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeoutShortRequest)
	defer cancel()

	ret, _, err := g.client.Organizations.IsMember(ctx, g.owner, user)

	return ret, err
}
