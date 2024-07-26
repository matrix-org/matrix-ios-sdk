# Contributing to Matrix iOS SDK, Kit and Element-iOS

Everyone is welcome to contribute code to matrix-ios-sdk, matrix-ios-kit,
element-ios, provided that they are willing to license their contributions
under the same license as the project itself. We follow a simple
'inbound=outbound' model for contributions: the act of submitting an
'inbound' contribution means that the contributor agrees to license the code
under the same terms as the project's overall 'outbound' license - in this case,
Apache Software License v2 (see [LICENSE](LICENSE)).

To simplify project management, Matrix iOS SDK and Matrix iOS Kit issues are
managed in the Element-iOS
[repository](https://github.com/vector-im/element-ios/issues).

## How to contribute

The preferred and easiest way to contribute changes to the project is to fork
it on GitHub, and then [create a pull request](https://docs.github.com/en/github/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/about-pull-requests) to ask us to pull your changes
into our repo.

We use GitHub's pull request workflow to review the contribution, and either
ask you to make any refinements needed or merge it and make them ourselves.

Things that should go into your PR description:

- References to any bugs fixed by the change (in GitHub's `Fixes` [notation](https://docs.github.com/en/issues/tracking-your-work-with-issues/linking-a-pull-request-to-an-issue#linking-a-pull-request-to-an-issue-using-a-keyword))
- Notes for the reviewer that might help them to understand why the change
is necessary or how they might better review it
- Screenshots or videos if applicable

Your PR must also:

- be based on the develop branch
- include a changelog file entry (see [below](#changelog))
- include a [sign off](#sign-off)

## Attribution

Everyone who contributes anything to Matrix is welcome to be listed in the
[AUTHORS.rst](AUTHORS.rst) file for the project in question. Please feel free
to include a change to AUTHORS.rst in your pull request to list yourself and
a short description of the area(s) you've worked on. Also, we sometimes have
swag to give away to contributors - if you feel that Matrix-branded apparel is
missing from your life, please mail us your shipping address to <em>matrix at
matrix.org</em> and we'll try to fix it :).

## Changelog

All changes, even minor ones, need a corresponding changelog / newsfragment
entry. These are managed by [Towncrier](https://github.com/twisted/towncrier).

To create a changelog entry, make a new file in the `changelog.d` directory
named in the format of `ElementIOSIssueNumber.type`. The type can be one of the
following:

- `feature` for a new feature
- `change` for updates to an existing feature
- `bugfix` for bug fix
- `api` for an api break
- `i18n` for translations
- `build` for changes related to build, tools, CI/CD
- `doc` for updates to the documentation
- `wip` for anything that isn't ready to ship and will be enabled at a later date
- `misc` for other changes

This file will become part of our [changelog](CHANGES.md) at the next
release, so the content of the file should be a short description of your
change in the same style as the rest of the changelog. The file must only
contain one line. It can contain Markdown formatting. It should start with the
area of the change (screen, module, ...) and end with a full stop (.) or an
exclamation mark (!) for consistency.

Adding credits to the changelog is encouraged, we value your
contributions and would like to have you shouted out in the release notes!

For example, a fix for an issue #1234 would have its changelog entry in
`changelog.d/1234.bugfix`, and contain content like:

> Voice Messages: Fix a crash when sending a voice message. Contributed by
> Jane Matrix.

If there are multiple pull requests involved in a single bugfix/feature/etc,
then the content for each `changelog.d` file should be the same. Towncrier will
merge the matching files together into a single changelog entry when we come to
release.

There are exceptions on the `ElementIOSIssueNumber.type` entry format. Even if
it is not encouraged, you can use:

- `pr-[PRNumber].type` for a PR with no related issue
- `sdk-[iOSSDKIssueNumber].type` for a PR related a matrix-ios-sdk issue
- `kit-[iOSKitIssueNumber].type` for a PR related a matrix-ios-kit issue
- `x-nolink-[AnyNumber].type` for a PR with a change entry that will not have a link automatically appended. It must be used for internal project update only. `AnyNumber` should be a value that does not clash with existing files.

To preview the changelog for pending changelog entries, use:

```bash
$ towncrier build --draft --version 1.2.3
```

## Sign off

In order to have a concrete record that your contribution is intentional
and you agree to license it under the same terms as the project's license, we've adopted the
same lightweight approach that the Linux Kernel
[submitting patches process](
https://www.kernel.org/doc/html/latest/process/submitting-patches.html#sign-your-work-the-developer-s-certificate-of-origin>),
[Docker](https://github.com/docker/docker/blob/master/CONTRIBUTING.md), and many
other projects use: the DCO (Developer Certificate of Origin:
<http://developercertificate.org/>). This is a simple declaration that you wrote
the contribution or otherwise have the right to contribute it to Matrix:

```text
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.
660 York Street, Suite 102,
San Francisco, CA 94110 USA

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.

Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```

If you agree to this for your contribution, then all that's needed is to
include the line in your commit or pull request comment:

```text
Signed-off-by: Your Name <your@email.example.org>
```

Git allows you to add this signoff automatically when using the `-s`
flag to `git commit`, which uses the name and email set in your
`user.name` and `user.email` git configs.
