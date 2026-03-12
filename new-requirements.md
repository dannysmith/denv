# New Requirements after research

If we temporarily work on the assumption that that we are going to have container or VM of some sort running locally for development, I can imagine something like this:

1. The files in the actual *repo* are mounted to my local filesystem (or perhaps more accurately: a folder on my local FS is mounted into the container). I can work with THEM using a normal local terminal session, my editor (VSCode/Cursor etc), Finder or any other tool. The container only has access to them and it's internal filesystem.
2. I run `claude` INSIDE the container. It has access only to the mounted project files and can therefor run with very loose permissions. If it accidentally runs `rm -rf ~` it doesn't matter. It is only able to accidentally exfiltrate data in the repo or any keys available on the container (claude, gh, project-related keys etc).
3. When I need to shell into the container myself to look at anything *outside* of the mounted project (eg `/tmp`) I can do that hand have a *kinda* similar shell environment to what I have locally, but it doesn't need to be perfect since most of my terminal work with a projects files will be IN THE PROJECT DIR ON MY LOCAL DISK.

This means that by default, the container primarly needs to be pre-configured with **the tools which I want Claude Code to use**. That probably looks something like this...


## Shell

ZSH (and *possibly* oh-my-zsh if really nececarry) with SOME of the most commonly-used shortcuts/features in `/.dotfiles/zshrc` and `/.dotfiles/commonrc`.

## Runtimes etc

Latest stable Python, Node and Rust installations, ideally managed via 

- bun/bunx (TS/JS)
- uv/uvx (Python)
- Whatever Rust uses for this by default

These should also be what we use to execute node packages or Python packages and if needed to install any global packages for them. They will also be the default package managers used within projects.

## Global CLI Tools Available

In addition to the standard tools I would expect to have available on any container or machine (git, vim, curl etc etc):

- gh
- claude
- playwright-cli
- defuddle - https://github.com/kepano/defuddle
- showboat - https://github.com/simonw/showboat
- rodney - https://github.com/simonw/rodney
- chartroom - https://github.com/simonw/chartroom
- ffmpeg (if it'snot massive)
- jq
- sqlite
- tree
- ripgrep
- unzip
- ca-certificates
- [probably a few more generic CLI tools which make Claude Code better at various generic tasks and cannot be executed with `bunx` or `uvx` (or are run often enough they shouldn't be) etc]

## Global Tools Requiring User Auth

- `gh` - Auth'd via `gh login` and web interface
- `git` - Auth'd via `gh`
- `claude` - Auth'd via `gh login` and web interface

When I spin up a new container for a new project or recreate it for an old project, I only need to run `gh login` and `claude login` and then paste the URLs into a browser to authenticate via the web and have it working.

## Global Config

We would clearly need some basic configuration for the various tools that we need installed above in dotfiles on the container. Chief among these are likely to be for Claude Code. We'd need a global `CLAUDE.md` and `~/.claude` pre-configured with the right global instructions, Claude Plugins/Skills/Agents etc. Much like the CLI tools above. If we took this approach, I wouldn't expect the default setup for this stuff to mirror how I have my global claude config set up locally. There would certainly be similarities. But I expect this to look quite different. 

### Claude Plugins/Skills

- defuddle
- frontend-design
- css-expert

### MCPs

- mcp__context7__resolve-library-id
- mcp__context7__query-docs

### Global CLAUDE.md

See `GLOBAL_CLAUDE.md`

## FS Mounting to my local FS

By "syncing" the container's `~/my-project` to my local `~/dev/my-project` we remove the issues associated with getting to project files using VS Code Finder and my local terminal. We could also conceivably "sync" the container's `~/temp` to some local `/devcontainerstemp/my-project/` or something? Or I suppose we could simply "sync" the container's whole `~/` to my local in a similar way. 

**Possible concern**: This may end up dealing with A LOT of files (any project's `.git/` will likeley contain a million files on it's own). I'm not sure if there's a good efficient way of dealing with this kind of stuff.

## Container FS Persistance

I would very much like to not have to repeat this every time I launch a container Which is an indication that we should probably look at making these containers semi-persistant (ie they can be switched on or off without destroying their internal file systems, But they can also be destroyed and reliably recreated. If I need to, you know, clear up some disc space or whatever). In a similar way, if I'm just spinning down a container, you know, to go to bed and I'm gonna pick some work up sometime in the next few days, I would much prefer that the local file system, i.e. directories like `/tmp` or `/~` weren't wiped since there's likely to be a bunch of temporary files and working directories and perhaps installed tools and everything which Claude has installed to work on this project. And I d don't want to commit to the project repo.

# Concerns/Questions with this approach

- Duplication - if we keep these things completely separate, at present every single project will have its own ring fenced environment which will have its own installation of all of the core tools/frameworks/runtimes etc. Now the size of the containers on disk is one issue here, but not the major one. The major one is that if I'm running 5-10 of these Can currently all of that stuff is going to be loaded into RAM.
