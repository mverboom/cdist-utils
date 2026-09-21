#!/usr/bin/env node
// Exercise the report-field ordering in scriptserver/eq-builder.html with a
// minimal DOM stub, since the ordering only happens in the browser.
"use strict";

const fs = require("fs");
const path = require("path");

class El {
  constructor(tag) {
    this.tag = tag;
    this.children = [];
    this.options = [];
    // A real HTMLOptionsCollection has no forEach; shadow the array method so
    // the test catches that class of bug.
    this.options.forEach = undefined;
    this.attributes = {};
    this.style = {};
    this._text = "";
    this.selected = false;
    this.value = "";
    this.disabled = false;
    this.checked = false;
  }
  appendChild(child) {
    this.children.push(child);
    if (child.tag === "option") { this.options.push(child); }
    return child;
  }
  setAttribute(name, value) { this.attributes[name] = value; }
  get textContent() { return this._text; }
  set textContent(value) { this._text = value; this.children = []; }
}

const byId = {};
global.document = {
  getElementById(id) {
    if (!byId[id]) { byId[id] = new El("div"); }
    return byId[id];
  },
  createElement(tag) { return new El(tag); },
  createTextNode(text) { return { text: text }; },
};
global.window = {};
const storage = {};
global.localStorage = {
  getItem(key) {
    return Object.prototype.hasOwnProperty.call(storage, key) ? storage[key] : null;
  },
  setItem(key, value) { storage[key] = String(value); },
  removeItem(key) { delete storage[key]; },
};

const template = fs.readFileSync(
  path.join(__dirname, "..", "scriptserver", "eq-builder.html"), "utf8");
const catalog = {
  fields: [
    { name: "distro", hosts: 3, values: [{ value: "debian", hosts: 2 }] },
    { name: "fqdn", hosts: 3, values: [{ value: "h1", hosts: 1 }] },
    { name: "cpu_cores", hosts: 2, values: [{ value: "8", hosts: 1 }] },
  ],
  hosts: ["h1"], tags: ["tagA"], operators: [
    { name: "==", description: "exact" },
    { name: "exists", description: "exists" },
  ], modifiers: [
    { name: "trim", description: "strip whitespace" },
    { name: "~", description: "matching lines" },
  ],
  runner: "Explorer Query", actionBuilder: "Query builder",
  actionRun: "Run query",
};
const page = template.replace("__EQ_CATALOG__", JSON.stringify(catalog));
const script = page.match(/<script>([\s\S]*)<\/script>/)[1];

function fail(message) {
  console.error("FAIL: " + message);
  process.exit(1);
}

eval(script);

const pick = byId["reportpick"];
const add = byId["addreport"];
const run = byId["run"];
const reportlist = byId["reportlist"];

function addField(name) {
  pick.value = name;
  add.onclick();
}

addField("distro");
addField("fqdn");
if (!run.attributes.href.includes("Report=distro%2Cfqdn")) {
  fail("expected report order distro,fqdn in " + run.attributes.href);
}
if (byId["run-top"].attributes.href !== run.attributes.href) {
  fail("top Run link does not match the bottom one");
}
if (byId["reportorder"].textContent !== "distro,fqdn") {
  fail("expected preview 'distro,fqdn', got " + byId["reportorder"].textContent);
}

// Second list item's first button is the "up" button.
const second = reportlist.children[1];
const up = second.children.filter(function (c) { return c.tag === "button"; })[0];
up.onclick();

if (!run.attributes.href.includes("Report=fqdn%2Cdistro")) {
  fail("expected reordered report fqdn,distro in " + run.attributes.href);
}
if (byId["reportorder"].textContent !== "fqdn,distro") {
  fail("expected preview 'fqdn,distro', got " + byId["reportorder"].textContent);
}

// A field can only be added once.
addField("fqdn");
if (byId["reportorder"].textContent !== "fqdn,distro") {
  fail("duplicate report field was added: " + byId["reportorder"].textContent);
}

// Append a modifier from the dropdown.
const firstItem = reportlist.children[0];
const modsel = firstItem.children.filter(function (c) { return c.tag === "select"; })[0];
modsel.value = "trim";
modsel.onchange();
if (byId["reportorder"].textContent !== "fqdn:trim,distro") {
  fail("modifier not appended: " + byId["reportorder"].textContent);
}
if (!byId["run"].attributes.href.includes("Report=fqdn%3Atrim%2Cdistro")) {
  fail("modifier not in link: " + byId["run"].attributes.href);
}

// Edit a spec directly (for ~regex and chained modifiers).
const secondItem = reportlist.children[1];
const specInput = secondItem.children.filter(function (c) {
  return c.tag === "input";
})[0];
specInput.value = "distro:~^nginx:f2";
specInput.oninput();
if (byId["reportorder"].textContent !== "fqdn:trim,distro:~^nginx:f2") {
  fail("spec edit not applied: " + byId["reportorder"].textContent);
}

// Restore test: fresh DOM, seeded state, re-evaluate the page.
Object.keys(byId).forEach(function (key) { delete byId[key]; });
storage["eq.builder.state"] = JSON.stringify({
  conditions: [{ field: "fqdn", op: "==", value: "h1", negate: false }],
  connectors: [],
  reportOrder: ["distro"],
  hosts: ["h1"],
  tags: [],
  alltags: [],
});
eval(script);
if (byId["reportorder"].textContent !== "distro") {
  fail("report order not restored: " + byId["reportorder"].textContent);
}
if (!byId["preview"].textContent.includes("fqdn == h1")) {
  fail("condition not restored: " + byId["preview"].textContent);
}
if (!byId["run"].attributes.href.includes("Report=distro")) {
  fail("report not restored in link: " + byId["run"].attributes.href);
}
if (!byId["run"].attributes.href.includes("Hosts=h1")) {
  fail("hosts not restored in link: " + byId["run"].attributes.href);
}

byId["reset"].onclick();
if (byId["reportorder"].textContent !== "") {
  fail("reset did not clear the report fields");
}

console.log("ok");
