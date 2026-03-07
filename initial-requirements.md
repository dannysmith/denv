# Initial Requirements

## Current Situation

I currently keep my dev projects in `~/dev/` - each as a directory containing a git repo which is also on GitHub. I also occasionally work in `~/scratchpad/` when exploring new ideas and topics, and move any projects which I wanna keep to `~/dev/` (and push them to GH).

Claude Code is installed on my machine and has some high-level instructions available via my global ~/.claude/CLAUDE.md along with a bunch of skills etc. Most of these are available through my Claude Plugins. My local machine also has various command line tools installed with homebrew and properly configured.

So my development workflow is usually something like this:

1. Open my terminal (ghostty)
2. cd into a project in ~/dev/ or ~/scratchpad/
3. Run `claude`
4. Split my Ghostty pane so I have a new shell on the right and claude on the left
5. Open the project in cursor `c .`

I use Claude Code in the left part of my terminal for most of my work. I use the other terminal on the right for any commands I need to run myself. And also if I'm working on a web project, I'll probably split this again and you know run the Dev server or whatever over here.

And as work is happening in Claude Code, I am able to look at it in my text editor (cursor). I use this to manually edit markdown documents, manually review and edit code etc as you would expect. I also often use the Git integration of cursor to commit work which has been done by Claude Code or me. I do not tend to use the agentic or AI features of cursor.

## The Problem

While my `~/.claude/settings.json` has a list of tool calls which are always ok, and a list which are always denied, the former is fairly conservative because I don not want to let Claude Code run in YOLO mode on my actual machine. There are two main reasons for this: 1) it could run any command it wants (worst case: `rm-rf ~`, more likeley case: random global installs or changes to my dotfiles etc) and 2) my local filesystem contains a bunch of private info which could easily be accidentally leaked. One example of this is my obsidian vault in `~/notes/`, which I happily use Claude Code wo work with but only ever under my supervision. For that kind of thing, my current setup works perfectly fine.

HOWEVER, for working on coding projects. I am getting fed up with having to approve so many tool uses manually. While most projects have local settings which auto-allow Web Search and various common project-specific shell commands/tool uses, I'm not even really comfortable allowing YOLO use of WebFetch and `gh` because used together on my filesystem they are a potential "lethal trifecta" attack vector.

## What I Want

I basically want a way to replicate my local laptop based development setup in a ring-fenced environment for each project/repo, such that

1. Claude Code can freely do anything it wants **inside** that container: create/edit/download files etc(whether inside the project git repo or anywhere else), install global packages or tools it needs etc.
2. Claude Code can freely make READ requests to the internet via `WebFetch`, `WebSearch`, Context7, `curl`, `defuddle`, `gh`, `git` or any other CLI tool, MCP etc.
3. Claude Code can read my local filesystem if needed (eg I give it a path to a private note in obsidian, but only with my explicit confirmation each time)
4. Claude Code requires my confiemation to WRITE to the internet via `gh`, `git push` etc. This could probably be handled in the Claude settings for each project repository in the usual way.
5. I can freely work in a shell in a similar way to how I work localy: My shell, abailable CLI tools etc are available and configured to Just Work.
6. When running Claude Code, I can still drag files and images into the terminal and have them Just Work (ie Claude can read them).
7. I can open the actual project repo in Cursor/VSCode as I do right now.
8. When necessary, it is not too painful to open the actual project repo in other GUI apps (eg Finder, open certain files in Preview or whatever)
9. Claude code has a set of global instructions, settings, skills, agents, MCPs (and CLI tools etc) available. The starting point for this will be my local setup, But these may diverge over time. The point here is that ANY project I open in this environment should have the SAME baseline set of this - any per-project stuff will be configured in the actual project.

### Other Stuff

- The "template" ring-fenced environment shoud be common to all projects I open in it, in the same way my laptop is. Anything which diverges from this should be committed to the project Git repo. ie. If I delete an "environment" it should be possible to recreate it by A) Creating a new generic one with the repo in question on it and B) Running whatever scripts/setup that repo requires to install it's specific stuff. I should not lose anything that cannot be recreated by doing this.
- If we approach this with containers/VMs, we should be conscious of efficiency (RAM, CPU, Disk).

---

## Refined Requirements Summary

The following was established through a detailed Q&A conversation exploring the original requirements above.

### The Ring-Fence Boundary

- Claude Code has **full autonomy inside the environment**: filesystem, global installs, running scripts, local network, everything.
- **Internet reads are unrestricted**: web search, WebFetch, `curl`, `gh api GET`, `git fetch` (even to private repos with auth), package installs, MCP calls, etc.
- **Internet writes are gated**: `git push`, `gh pr create`, `gh api POST`, `gh issue create`, publish commands, or anything else that could visibly change state on GitHub or other remote services requires explicit confirmation. This can be enforced via Claude Code's own permission settings (per-project `settings.json` allowlists/denylists).
- **Host filesystem is inaccessible by default**. Occasional reads (e.g., referencing a note from `~/notes/`) should be possible with explicit per-request confirmation, but this is infrequent and not a critical workflow.

### Environment Lifecycle & Performance

- **Persistent environments**: environments survive across sessions (terminal close, laptop sleep, etc.). Recreating from scratch on each launch is too slow - waiting for global packages, language runtimes, project dependencies, repo cloning, etc. is not acceptable.
- **3-4+ concurrent environments** running simultaneously, possibly more over time as increased autonomy enables working on more projects in parallel.
- **Startup time**: a few seconds of spin-up is acceptable. A few minutes is not. The goal is: enter the environment and get straight to work.
- **Recreatable**: if an environment is deleted, it must be possible to recreate it from: A) a new generic base environment, B) the project's git repo, and C) whatever project-specific setup scripts/docs that repo contains. Nothing of value should be lost that isn't committed to git or part of the base template.

### Developer Experience

- **Editor**: Cursor/VS Code connecting remotely to the container (VS Code Remote Development) is acceptable. It doesn't need to be a locally-opened directory.
- **GUI app access**: occasionally needed (Finder, Preview, etc.) but infrequent. Should not be painful when needed, but doesn't need to be the primary workflow.
- **Image sharing with Claude Code**: the key requirement is speed. Current workflow: take a screenshot, switch to the Claude Code terminal, share it immediately. If copy-pasting images from the clipboard into Claude Code inside the container works, that's sufficient. A complicated system involving shared folders and specific file paths is not acceptable for this use case - it needs to be near-instant.
- **Port forwarding**: web application dev servers running inside the environment must be accessible in a browser on the host Mac (e.g., `localhost:3000`).
- **Playwright**: must work inside the environment via playwright-cli.

### Shell Experience

- The shell inside the environment should feel the same as working locally. This means: zsh, dev-related shell functions, zsh plugins, prompt, aliases, etc.
- Not everything from the host dotfiles is needed - non-dev stuff (macOS-specific utilities, personal tools unrelated to development) can be excluded.
- The actual specifics of what to include/exclude can be worked out during implementation. The intent is: when working in a shell inside the environment, it should feel familiar and productive - not like a bare-bones container.

### Global Configuration & Templating

- A **common base template** is shared across all environments, analogous to how the laptop itself is common to all projects.
- The starting point is a fork of the current local Mac setup (dotfiles, `~/.claude/` config, global CLAUDE.md, skills, MCPs, CLI tools).
- This fork will **intentionally diverge over time**:
  - The environment's global CLAUDE.md won't need instructions for things like the Obsidian vault (which will only ever be used locally on the Mac).
  - Claude Code command allowlists will be significantly more permissive inside the environment (that's the whole point).
  - The dotfiles will be a dev-focused subset, adapted for Linux compatibility.
  - Over time, if most development work moves to these environments, the local Mac config may shrink (less dev tooling needed locally) while the environment config grows.
- The environment's global config should be version-controlled independently from the local Mac config.

### Project Types & Operating System

- **Linux inside the environment is acceptable.** Danny is comfortable in Linux and uses very few macOS-specific CLI tools for development.
- Apple's Virtualization Framework is interesting as an option but not a requirement.
- Project types are varied (the base template should be language-agnostic, with project-specific runtimes/tools installed per-project). Specific considerations:
  - **Web apps**: need port forwarding to access dev servers from the host browser.
  - **Playwright**: must work inside the environment.
  - **Tauri apps**: these launch a native macOS application as their dev server, which cannot run inside a Linux container. This is a special case (not every project). A hybrid approach may be needed: Claude works on the code inside the environment, while the Tauri dev server runs on the host Mac with the repo mounted/shared. Other solutions may exist.

### Supervision Model & Autonomy

The ring-fenced environment naturally enables a **spectrum of supervision levels** without any design distinction:

- **Active supervision, fewer prompts**: working on an important codebase, checking in on progress often, prompting Claude to work in smaller chunks for review/commit in Cursor. The ring-fence simply removes the friction of approving routine tool calls.
- **Semi-attended**: Claude is working, Danny is on his laptop doing other things, occasionally checking in.
- **Fully unattended / kick-off-and-walk-away**: for exploratory or research tasks. Example: create an empty repo with a single `initial-reqs.md`, tell Claude to go research, and walk away. Claude should be able to install whatever it needs, write scripts, run them, search the web, make API calls - anything - and produce a result (e.g., `research.md` with findings). This works because nothing in this workflow requires writing outside the ring-fence or accessing host files.
- The laptop can be assumed to stay awake even when walked away from.

### Read vs Write Gating: The Nuance

The distinction between "free reads" and "gated writes" is about **observable side effects on external services**, not about the tool or protocol used:

- `gh api` doing a GET: free. `gh api` doing a POST/PUT/DELETE: needs confirmation.
- `git fetch` (even authenticated, even to private repos): free. `git push`: needs confirmation.
- `curl` fetching a URL: free. `curl -X POST` to an external API: needs confirmation.
- Package installs (`bun install`, `pip install`): free (these read from registries and write locally).
- Any command that publishes, posts, creates issues/PRs, sends messages, or modifies remote state: needs confirmation.

The specific implementation of this gating (which commands are allowlisted, which need approval) is a detail to work out during implementation. The intent is clear: **Claude Code should never be able to change the state of the outside world without explicit approval.**

---

## Detailed Discussion Notes

The following captures the full context of the requirements conversation for reference by future sessions.

### On Environment Persistence (Q: ephemeral or persistent?)

> I don't really care whether it's persistent or recreated so long as I can just get straight to work. But I can't imagine us making recreation on each launch efficient enough to achieve that. Like if I open up a Java project in this environment, I'm not gonna want to wait for a load of global packages and then Java and then a load of project specific packages and all the rest to get installed and the repo cloned and all the rest of it. I wanna be able to open the project and get straight to work.

**Conclusion**: persistent environments. The user doesn't have a philosophical preference for persistence vs ephemeral - they care about the UX outcome (instant start). Persistence is the practical path to achieving that.

### On Concurrency (Q: one at a time or multiple?)

> Multiple projects at once - typically 3-4 right now, but with this setup and Claude Code able to act more autonomously it may be a few more.

**Conclusion**: resource efficiency matters. 3-4 environments running simultaneously is the baseline; could grow to 5-6+. This rules out heavyweight approaches (e.g., multiple full macOS VMs).

### On Editor Access (Q: local directory or remote connection OK?)

> I'd be fine with Cursor connecting remotely to the container. But bearing in mind my requirement to access the files with other apps, that may or may not make sense. I don't access files with other apps very regularly. But it would be quite inconvenient to me if I couldn't do that when I needed to.

**Conclusion**: Cursor Remote is acceptable as the primary editor workflow. Occasional GUI app access (Finder, Preview) is a secondary requirement - infrequent but should be possible without major pain. This likely means the project directory needs to be accessible from the host somehow, even if the primary access is remote.

### On Image Sharing (Q: drag-and-drop essential or just easy image sharing?)

Two current patterns:
1. Drag a file (usually an image) from the Mac desktop into Claude Code's terminal
2. Take a screenshot and drag it from the macOS screenshot preview in the bottom right corner

Both paste a local file path under the hood. Inside a container, these host paths don't exist.

> If Claude Code supports pasting images into it inside a container then I think the image thing is solved. All I need to do is work out on my Mac a very easy way of copying an image or screenshot I've just taken and pasting it in. I don't really care how I get images in here, so long as it's extremely quick. A common workflow for me is taking a screenshot, then quickly switching spaces to my Claude Code terminal and then just dragging it from the preview in the bottom right. The point here is doing it quickly. If there's some complicated system of shared folders where I have to reference the name of it and put it in a particular folder - that's not gonna be good when I have to take screenshots and give them to Claude.

**Conclusion**: the actual requirement is "fast image sharing", not specifically "drag-and-drop file paths." Clipboard-based image paste would be ideal if supported. The solution needs to be near-instant and not involve any file management choreography.

### On Local Filesystem Reads (Q: how does this work in practice?)

> This doesn't come up that frequently. In a non-containerised CC session I'd grab the path of a file outside the current project and say something like "Look at `~/notes/some-file.md` it may be of help" and then CC would ask my permission to read a file outside its project.

**Conclusion**: infrequent, nice-to-have. The current mechanism is simple (paste path, Claude asks permission). In a containerised setup, some mechanism would be needed (e.g., a command to copy a host file into the container on demand, or a read-only mount with confirmation). Not a critical workflow - can be a secondary consideration.

### On Global Config Divergence (Q: intentional or accidental drift?)

> Intentionally. One solution to getting all this config is simply copying over my local configurations. That would certainly be a good starting point, but I can imagine that over time if we get this right, I will end up doing most of my development in these environments - meaning my local config would need less stuff to do with development work. As an example, my current global CLAUDE.md includes instructions for working with things like my Obsidian vault, which I will only ever do locally on my MacBook. That stuff wouldn't need to be in these containers. An obvious other example is the allowlists for Claude commands which will definitely be different on my laptop to in this env. Likewise these environments are not gonna need everything which is currently in my dotfiles.

**Conclusion**: the environment's global config is a deliberate fork. Start from the local setup, then prune and adapt. Version-control it independently. Expect the two configs to diverge over time as the environment becomes the primary dev context and the local Mac becomes more of a personal/non-dev machine.

### On Project Types and OS Constraints (Q: what languages, any platform constraints?)

> This is a detail we can expand on later, but generally it shouldn't matter. Two things that spring to mind: if I'm working on a web application I obviously need to be able to access that in a browser easily on my actual machine (i.e., what would currently be localhost:1234). Whatever OS this environment runs also needs to be able to run Playwright via playwright-cli. And one thing that may be difficult if we use Docker: some of my projects are Tauri apps, so running the dev server actually launches a macOS application. That is by no means every project, and it may well be that the only solution there if we are using some kind of VM/container is to mount the repo as a shared folder with Claude working on it in the VM and me running the dev server locally. Of course there may be other solutions I haven't thought of yet.

**Conclusion**: language/runtime agnostic base template. Port forwarding and Playwright are hard requirements. Tauri is a known special case that may need a hybrid approach - not a blocker for the overall design.

### On Shell Customization (Q: how much of current shell config matters?)

> Most of it I think. At least most of the stuff related to development. I would want my shell to feel the same whether I'm working locally or in one of the environments. That means most of my shell functions, zsh plugins, prompt, etc. But there are obviously certain things in my dotfiles (and also certain CLI tools) which I use and have very little to do with development that wouldn't be needed here. The actual details of this stuff is definitely something we can work out further down the line. But it's important that you get my intent here despite.

**Conclusion**: dev-related shell config should be ported. The shell experience should feel familiar. Non-dev tools/config can be excluded. Details deferred to implementation, but the bar is "feels like my normal shell for dev work."

### On Read/Write Gating Nuance (Q: how precise does the gating need to be?)

> That's a brilliant question because `gh api` is one of my annoying issues for exactly that reason. What I'd really like is for agents to be free with `gh api` GETs and have to ask me for `gh api` POSTs etc. My intent is exactly "anything that could visibly change state on GitHub/remote services needs confirmation." As another example, I'm fine with Claude Code doing an authenticated `git fetch` to a private repo, so long as I know it can't do a `git push` or `gh issue create` or `mytool publish danny-stuff` without my thumbs up.

**Conclusion**: the gating is intent-based (observable side effects), not tool-based. This has implementation implications - simple allowlisting by command name may not be sufficient. May need pattern-based rules (e.g., allow `gh api /repos/{owner}/{repo}/...` but require confirmation for `gh api -X POST ...`). The specific rules can be worked out during implementation, but the architecture needs to support this level of granularity.

### On Supervision Model (Q: fewer prompts while watching, or kick-off-and-walk-away?)

> "Fewer permission prompts while I'm actively working" enables "kick off a task, walk away, check back later" in a way that's impossible with my current way of working. My actual answer depends on the project. For certain projects I am likely to be sat on my laptop while Claude is working and I'm literally just looking to have it run a little bit longer without having to come and give it permission for stuff. But an example of a kick-off-walk-away thing might be an exploratory task in a brand-new empty repo I've created, where I've just written a single initial-reqs.md doc. In that case my initial instructions would tell it to go away and do whatever. And I would want that to be able to install whatever it wanted, write whatever scripts it wanted, run whatever scripts it wanted, look online, make calls to the web and all the rest of it. And I'd expect to come back and see a report written to research.md in that repo, perhaps with a load of intermediary code it wrote. The key point is that it can do all of that in a ring-fenced environment because it doesn't need access to any files elsewhere on my local machine and none of that requires WRITING anywhere outside the ring-fence.
>
> If I'm working on a project where I care more about the codebase I'll likely be A) checking in on progress more often, B) prompting the agent to work in smaller chunks so I can review/commit myself in Cursor. But it doesn't really seem important to distinguish between these ways of working (or rather the sliding scale between them) because any environment which is ring-fenced in the way we're discussing will allow for both ends.
>
> We can assume that my laptop will be awake even if I've walked off.

**Conclusion**: the ring-fence is what enables the full spectrum of supervision. No special infrastructure needed for "unattended mode" vs "supervised mode" - the same environment serves both. The design should not distinguish between them. Laptop stays awake (no need for cloud hosting or remote servers to keep things running).

### On Linux vs macOS Inside the Environment (Q: is Linux acceptable?)

> I'm comfortable in a Linux environment and use very few macOS-specific CLI tools for dev. I'm certainly interested in Apple's Virtualization Framework as an option but it's not at all a requirement. My dev projects mostly do not require any macOS-specific stuff, with the exception of Tauri projects.

**Conclusion**: Linux is fine. This opens up Docker containers as the most resource-efficient option. macOS VMs (via Virtualization.framework or similar) remain an option but are not required. Tauri is the one known exception where macOS is needed - to be handled as a special case.
