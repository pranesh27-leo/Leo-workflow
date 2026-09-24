'use strict';
// desc: set up a repository for leo
// usage: leo init [--force]
//
// Installs, and never overwrites without --force:
//   AGENTS.md          short, loaded every session, read by every agent
//   CLAUDE.md          one-line bridge to AGENTS.md
//   CONTEXT.md         what this project is
//   ARCHITECTURE.md    how the pieces fit
//   CODE_REVIEW.md     what a finding has to clear — cycle two argues against it
//   RULES.md           an index of .leo/rules/, with the reason for each
//   SESSION.md         where this session stands — written by leo, never by you
//   .leo/workflow.md   the loop the agent follows, read on demand
//   .leo/plans/        one directory per plan: P1, P2, ... each with its tasks
//   .leo/tools/        one per capability: how to use it, what it needs
//   .leo/config        TEST_CMD and friends
//   .leo/rules/        one file per lesson learned, enforced by `leo check`

const fs = require('fs');
const path = require('path');
const { info, dim, ok } = require('../lib/ui');
const { needRepo } = require('../lib/ctx');
const { mkdirp, readIfFile } = require('../lib/fsx');
const { BUILTIN_CAPS } = require('../lib/caps');

const CONFIG_BODY = `# leo config — plain shell, committed with the repo.

# How \`leo check\` verifies the change. Without this, leo can check that the
# work was scoped honestly but not that it works.
TEST_CMD=""
# TEST_CMD="go test ./..."
# TEST_CMD="npm test"
# TEST_CMD="pytest -q"
`;

// The plan, the manifest, the session and the recorded-but-unlanded cycles
// are working state; they end up in commit messages, so they should not also
// be tracked as files. SESSION.md and .leo/current join them: both say where
// one working tree is at one moment. .leo/plans/ is deliberately NOT here --
// a plan is the reasoning behind a change, it outlives the change, and it
// belongs to everyone who later has to ask why a line is the way it is.
const IGNORES = [
  '.leo/plan.md', '.leo/manifest.md', '.leo/session', '.leo/tasks/',
  '.leo/commits/', '.leo/used', '.leo/current', 'SESSION.md',
];

function run(ctx) {
  needRepo(ctx);
  process.chdir(ctx.root);

  const force = ctx.argv[0] === '--force';

  const put = (tmpl, dest) => {
    if (fs.existsSync(dest) && !force) {
      dim('  skip    ' + dest + ' (exists)');
      return;
    }
    mkdirp(path.dirname(dest));
    fs.writeFileSync(dest, ctx.assets.tmplRead(tmpl));
    info('  install ' + dest);
  };

  for (const d of ['.leo/rules', '.leo/integrations', '.leo/tasks', '.leo/tools',
                   '.leo/skills', '.leo/reviews', '.leo/plans']) {
    mkdirp(d);
  }

  put('AGENTS.md', 'AGENTS.md');
  put('CLAUDE.md', 'CLAUDE.md');
  // What this repository is, as opposed to how to work in it. AGENTS.md loads
  // on every request and has to stay short enough that a weak model reads to
  // the end; everything repo-specific goes here instead.
  put('CONTEXT.md', 'CONTEXT.md');
  put('workflow.md', '.leo/workflow.md');
  put('rule.md', '.leo/rules/EXAMPLE.md');
  // The rubric cycle two argues against. Installed rather than read from the
  // install for the same reason .leo/workflow.md is a copy: a team amends its
  // own standards, and a review that cites a file the repo cannot show is not
  // citing anything.
  put('review/STANDARDS.md', 'CODE_REVIEW.md');
  // The three that answer the questions AGENTS.md is too short to answer. All
  // three are read on demand, which is what lets them be as long as they are
  // useful.
  put('ARCHITECTURE.md', 'ARCHITECTURE.md');
  put('RULES.md', 'RULES.md');
  // A placeholder only. The real one is written by the exit hook on the way
  // out of this very command, so what lands here is overwritten seconds later
  // with the truth. It exists so that a fresh clone has the file before
  // anybody runs anything, rather than a dangling reference in AGENTS.md.
  put('SESSION.md', 'SESSION.md');
  // A README rather than a sample adapter: leo loads every adapter in that
  // directory, so a template that shipped as one would load itself and show
  // up as a capability nobody asked for.
  put('integration.md', '.leo/integrations/README.md');

  // One per capability leo ships with. Driven off BUILTIN_CAPS so adding a
  // capability cannot forget its doc.
  for (const cap of BUILTIN_CAPS) {
    if (!ctx.assets.tmplHas('tools/' + cap + '.md')) continue;
    put('tools/' + cap + '.md', path.join('.leo', 'tools', cap + '.md'));
  }

  // The grill is stage one of the loop, and it is somebody else's work: these
  // are copied in unmodified so the definition of a grill cannot change under
  // a repository between two sessions.
  for (const s of ['skills/grilling/SKILL.md', 'skills/grill-me/SKILL.md',
                   'skills/LICENSE', 'skills/README.md']) {
    if (!ctx.assets.tmplHas(s)) continue;
    put(s, path.join('.leo', s));
  }

  // ...and again, where the agent's runtime will actually find them.
  //
  // This is the bug that made the whole thing worth fixing: leo vendored the
  // grill into .leo/skills/, no runtime reads that path, and the skill
  // shipped doing nothing for anyone who did not wire it up by hand.
  // .leo/skills/ stays the canonical copy and this is the working one.
  //
  // Claude Code only, and leo says so rather than guessing. Cursor, Codex and
  // Aider each have their own convention; inventing three more paths from
  // memory is how you get three more dangling pointers instead of one.
  for (const s of ['grilling', 'grill-me']) {
    if (!ctx.assets.tmplHas('skills/' + s + '/SKILL.md')) continue;
    put('skills/' + s + '/SKILL.md', path.join('.claude', 'skills', s, 'SKILL.md'));
  }

  if (!fs.existsSync('.leo/config') || force) {
    fs.writeFileSync('.leo/config', CONFIG_BODY);
    info('  install .leo/config');
  }

  const gitignore = readIfFile('.gitignore');
  const have = gitignore === null ? [] : gitignore.split('\n');
  for (const entry of IGNORES) {
    if (have.indexOf(entry) !== -1) continue;
    // Appended, and the newline goes in front when the file does not end in
    // one: otherwise the first entry lands on the tail of whatever the
    // developer's last line was and neither pattern matches anything.
    const cur = readIfFile('.gitignore');
    const sep = (cur === null || cur === '' || cur.endsWith('\n')) ? '' : '\n';
    fs.appendFileSync('.gitignore', sep + entry + '\n');
    have.push(entry);
    info('  update  .gitignore (' + entry + ')');
  }

  process.stderr.write('\n');
  ok('ready');
  dim('  1. fill in AGENTS.md — delete every placeholder you do not need');
  dim('  2. set TEST_CMD in .leo/config');
  dim('  3. leo agents --ask   — put the tool choice to the developer, then');
  dim('     leo agents --auto  — write their answer into AGENTS.md');
  dim('  4. start a change: leo plan "<name>"   (it becomes P1)');
  dim('  5. make CODE_REVIEW.md yours — it is what cycle two argues against');
  return 0;
}

module.exports = { run };
