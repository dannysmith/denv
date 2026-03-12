# Claude Code Tool Permissions (Current Mac Setup)

> **Context**: Documents Danny's current global Claude Code permission settings (`~/.claude/settings.json`) as of March 2026, and lists commands that should be auto-allowed inside the ring-fenced container but are currently gated on the Mac. This serves as a reference for designing the container's permission model (see PLAN.md Phase 5).

My current Global Claude settings have these permissions:

```json
"permissions": {
  "allow": [
    "MCP(playwright:*)",
    "MCP(context7:*)",
    "Read(*)",
    "LS(*)",
    "Bash(ls:*)",
    "Bash(ll:*)",
    "Bash(dir:*)",
    "Bash(cat:*)",
    "Bash(head:*)",
    "Bash(tail:*)",
    "Bash(file:*)",
    "Bash(stat:*)",
    "Bash(wc:*)",
    "Bash(find:*)",
    "Bash(pwd)",
    "Bash(cd:*)",
    "Bash(grep:*)",
    "Bash(awk:*)",
    "Bash(sed:*)",
    "Bash(sort:*)",
    "Bash(uniq:*)",
    "Bash(diff:*)",
    "Bash(comm:*)",
    "Bash(whoami)",
    "Bash(date)",
    "Bash(uname:*)",
    "Bash(env)",
    "Bash(printenv:*)",
    "Bash(which:*)",
    "Bash(whereis:*)",
    "Bash(type:*)",
    "Bash(git status)",
    "Bash(git log:*)",
    "Bash(git show:*)",
    "Bash(git diff:*)",
    "Bash(git branch:*)",
    "Bash(git remote:*)",
    "Bash(git config --get:*)",
    "Bash(git rev-parse:*)",
    "Bash(gh repo view:*)",
    "Bash(gh pr list:*)",
    "Bash(gh pr view:*)",
    "Bash(gh issue list:*)",
    "Bash(gh issue view:*)",
    "Bash(gh status)",
    "Bash(echo:*)",
    "Bash(printf:*)",
    "Bash(base64:*)",
    "Bash(basename:*)",
    "Bash(dirname:*)",
    "Bash(realpath:*)",
    "Bash(readlink:*)",
    "Skill(tdn@tdn-marketplace:*)",
    "Skill(tdn-claude-plugin:task-management)",
    "Skill(css-expert)",
    "Bash(tree:*)",
    "Bash(cargo check:*)",
    "Bash(pnpm run check:*)",
    "Bash(bun run check:*)",
    "Bash(npm run check:*)",
    "Bash(tdn context:*)",
    "Bash(tdn list:*)",
    "Bash(tdn show:*)",
    "WebFetch(domain:github.com)",
    "WebFetch(domain:ui.shadcn.com)",
    "WebFetch(domain:docs.anthropic.com)"
  ],
  "deny": [
    "Bash(sudo:*)",
    "Bash(su:*)",
    "Bash(reboot)",
    "Bash(shutdown:*)",
    "Bash(halt)",
    "Bash(poweroff)",
    "Bash(useradd:*)",
    "Bash(userdel:*)",
    "Bash(usermod:*)",
    "Bash(passwd:*)",
    "Bash(chpasswd:*)",
    "Bash(mkfs:*)",
    "Bash(fdisk:*)",
    "Bash(parted:*)",
    "Bash(mount:*)",
    "Bash(umount:*)",
    "Bash(exec:*)",
    "Bash(eval:*)",
    "Bash(source:*)",
    "Bash(.:*)",
    "Bash(bash:*)",
    "Bash(sh:*)",
    "Bash(zsh:*)",
    "Bash(fish:*)",
    "Bash(crontab:*)",
    "Bash(iptables:*)",
    "Bash(ufw:*)"
  ]
},
```

The allow list is intended to be somewhat permissive for commands which cannot do any damage. And the denialist is supposed to block extremely damaging commands. If we are working in a container, I would expect the default deny list to be extremely small because In that environment Claude can use pseudo, it can evaluate code, it can executive things, it can mount things, all the rest of it. I don't care if it does those things because If it breaks the machine. It doesn't matter. We'll just recreate it.

## Commands I'd Want To Add to the Default Allow List

These are commands which I currently want to app approve one by one, but are very tedious when doing so on my local machine. I wouldn't have a concern with these running without my confirmation in a ring fence container. The main rule here is that if it is simply getting stuff from the internet and doing things with it on the machine, it's completely fine and I don't want to interact or asked about it. If it is writing stuff to the internet, then I do. 

- WebFetch (any URL)
- WebSearch
- curl
- defuddle
- `gh api` for any READ-ONLY operation (but not for commands which mutate state on github which is outside the projects repo). This might require us building some kind of wrapper around this. But there might also be a better way of doing that. Just with clawed instructions or skills. 
