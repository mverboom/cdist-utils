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
  ], modifiers: [],
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

console.log("ok");
