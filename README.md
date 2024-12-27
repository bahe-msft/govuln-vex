# govuln-vex

This is an experimental project for automating [OpenVEX][] documents generation via [govulncheck][]

[OpenVEX]: https://github.com/openvex
[govulncheck]: https://pkg.go.dev/golang.org/x/vuln/cmd/govulncheck

## Why?

CVE reports are great and healthy project/community should maintain processes for mitigating vulnerabilities in time.
However, vulnerabilities come up everyday, it's hard to keep track of them and it's even hard to patch every single one of them *in time*.

As of 2024 Dec, a common pitfall for many CVE scanners is that they only scan the dependencies / SBOM of a component.
But in reality, referencing a vulnerable package doesn't mean the component is vulnerable as the vulnerable code path might not be reachable.
In Go's ecosystem, govulncheck provides an enhanced approach to provide more accurate results by analyzing the vulnerabilities in the source code level. With the analyze results, we can generate OpenVEX reports to help developers and users to understand the security status of the component.

This project aims to automate this process in a set of selected repositories and collect deltas in time.

## Reports

You can find the generated report in [report.md](report.md).
