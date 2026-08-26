"use strict";

const state = {
  data: null,
  feature: null,
  search: "",
  assessment: "all",
  selectedBehaviorId: null,
};

const labels = {
  covered: "Covered",
  verified_candidate: "Verified candidate",
  proof_not_run: "Proof not run",
  proof_partial: "Proof partial",
  proof_blocked: "Proof blocked",
  test_gap: "Test gap",
  failing_proof: "Failing proof",
  intent_open_question: "Intent open question",
  implementation_candidate: "Implementation candidate",
  implementation_partial: "Implementation partial",
  implementation_not_evidenced: "Implementation not evidenced",
  implementation_gap_reviewed: "Reviewed implementation gap",
  stale_evidence: "Stale evidence",
  investigate: "Investigate",
  candidate: "Candidate",
  partial: "Partial",
  not_evidenced: "Not evidenced",
  confirmed: "Confirmed",
  rejected: "Rejected",
  unclear: "Unclear",
  active: "Active",
  provisional: "Provisional",
  deprecated: "Deprecated",
  verified: "Verified",
  declared: "Declared, not run",
  stale: "Stale",
  missing: "Missing",
  invalid: "Invalid",
  blocked: "Blocked",
  failed: "Failed",
  passed: "Passed",
  not_run: "Not run",
  missing_file: "Missing file",
  not_applicable: "Not applicable",
};

const testTypeLabels = {
  unit: "Unit test",
  integration: "Integration test",
  contract: "Contract test",
  native_unit: "Native unit test",
  device: "Device / simulator test",
};

function displayLabel(value) {
  return labels[value] || String(value).replaceAll("_", " ");
}

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = String(text);
  return node;
}

function statusPill(value) {
  const template = document.querySelector("#status-template");
  const pill = template.content.firstElementChild.cloneNode(true);
  pill.classList.add(value);
  pill.textContent = displayLabel(value);
  return pill;
}

function metricCard(value, label) {
  const card = element("div", "metric-card");
  card.append(element("span", "metric-value", value));
  card.append(element("span", "metric-label", label));
  return card;
}

function renderMetrics(target, metrics) {
  target.replaceChildren(...metrics.map(([value, label]) => metricCard(value, label)));
}

function renderProvenance() {
  const { repository, graphs } = state.data;
  const graph = graphs.architecture;
  const entries = [
    ["revision", repository.shortRevision],
    ["application tree", repository.applicationDirty ? "dirty" : "clean"],
    ["architecture graph", graph.freshness.status],
    ["graph fingerprint", graph.fingerprint],
    ["full fallback", graphs.fullFallback.available ? "available / freshness unchecked" : "missing"],
  ];
  const container = document.querySelector("#provenance");
  container.replaceChildren(
    ...entries.map(([label, value]) => {
      const row = element("span");
      row.append(element("strong", "", `${label}: `));
      row.append(document.createTextNode(value));
      return row;
    }),
  );
  if (graph.freshness.newerSource) {
    const warning = element("span", "", `newer source: ${graph.freshness.newerSource}`);
    container.append(warning);
  }

  const health = document.querySelector("#health-badge");
  const current = graph.freshness.status === "current" && !repository.applicationDirty;
  health.className = `health-badge ${current ? "current" : "warning"}`;
  health.textContent = current ? "Evidence inputs current" : "Evidence needs attention";
}

function renderProjectSummary() {
  const summary = state.data.summary;
  renderMetrics(document.querySelector("#summary-cards"), [
    [summary.features, "Features"],
    [summary.requiredBehaviors, "Required behaviors"],
    [summary.implementationCandidates, "Code candidates"],
    [summary.verified, "Currently verified"],
    [summary.proofNotRun, "Proof not run"],
    [summary.openIntent + summary.failingProof, "Needs decision"],
  ]);
  document.querySelector("#generated-at").textContent =
    `Generated ${new Date(state.data.generatedAt).toLocaleString()}`;
}

function renderFeatureHeader() {
  const feature = state.feature;
  document.querySelector("#feature-kicker").textContent =
    `${feature.id} · PRD ${feature.prd.version} · ${feature.intentStatus}`;
  document.querySelector("#feature-title").textContent = feature.title;
  document.querySelector("#feature-description").textContent = feature.description;
  const link = document.querySelector("#prd-link");
  link.href = `../${encodeURI(feature.prd.path)}`;
  link.hidden = !feature.prd.exists;
  renderMetrics(document.querySelector("#feature-summary"), [
    [feature.summary.requiredBehaviors, "Behaviors"],
    [feature.summary.implementationCandidates, "Code candidates"],
    [feature.summary.verified, "Verified"],
    [feature.summary.proofNotRun, "Proof not run"],
    [feature.summary.openIntent, "Open intent"],
  ]);
}

function populateAssessmentFilter() {
  const select = document.querySelector("#assessment-filter");
  select.replaceChildren();
  const all = element("option", "", "All assessments");
  all.value = "all";
  select.append(all);
  const statuses = [...new Set(state.feature.behaviors.map((row) => row.assessment.status))].sort();
  for (const status of statuses) {
    const option = element("option", "", displayLabel(status));
    option.value = status;
    select.append(option);
  }
}

function selectFeature(featureId) {
  const selected = state.data.features.find((feature) => feature.id === featureId);
  if (!selected) return;
  closeBehaviorDetails(false);
  state.feature = selected;
  state.search = "";
  state.assessment = "all";
  document.querySelector("#behavior-search").value = "";
  renderFeatureHeader();
  populateAssessmentFilter();
  renderBehaviorRows();
}

function populateFeatureSelect() {
  const wrapper = document.querySelector("#feature-selector-wrap");
  const select = document.querySelector("#feature-select");
  select.replaceChildren(
    ...state.data.features.map((feature) => {
      const option = element("option", "", feature.title);
      option.value = feature.id;
      return option;
    }),
  );
  select.value = state.feature.id;
  wrapper.hidden = state.data.features.length <= 1;
  select.addEventListener("change", (event) => selectFeature(event.target.value));
}

function behaviorMatches(behavior) {
  if (state.assessment !== "all" && behavior.assessment.status !== state.assessment) {
    return false;
  }
  if (!state.search) return true;
  const haystack = [
    behavior.id,
    behavior.title,
    behavior.plainDescription,
    behavior.requirement,
    ...behavior.sourceRefs,
    ...behavior.openQuestions.flatMap((question) => [
      question.id,
      question.title,
      question.prompt,
    ]),
  ]
    .join(" ")
    .toLocaleLowerCase();
  return haystack.includes(state.search);
}

function behaviorRow(behavior) {
  const row = element("tr");
  const isSelected = state.selectedBehaviorId === behavior.id;
  row.dataset.behaviorId = behavior.id;
  row.classList.toggle("is-selected", isSelected);
  const identity = element("td");
  const button = element("button", "behavior-button");
  button.type = "button";
  button.setAttribute("aria-controls", "behavior-details");
  button.setAttribute("aria-expanded", String(isSelected));
  button.append(element("strong", "", behavior.id));
  button.append(element("span", "behavior-title", behavior.title));
  button.append(
    element("span", "behavior-description", behavior.plainDescription),
  );
  button.addEventListener("click", () => openBehavior(behavior));
  identity.append(button);
  row.append(identity);

  const intent = element("td");
  intent.append(statusPill(behavior.intentStatus));
  row.append(intent);

  const implementation = element("td");
  implementation.append(statusPill(behavior.implementation.status));
  row.append(implementation);

  const verification = element("td");
  verification.append(statusPill(behavior.verification.status));
  row.append(verification);

  const assessment = element("td");
  assessment.append(statusPill(behavior.assessment.status));
  row.append(assessment);
  return row;
}

function renderBehaviorRows() {
  const behaviors = state.feature.behaviors.filter(behaviorMatches);
  document.querySelector("#behavior-rows").replaceChildren(...behaviors.map(behaviorRow));
  document.querySelector("#empty-state").hidden = behaviors.length !== 0;
}

function syncBehaviorSelection() {
  for (const row of document.querySelectorAll("#behavior-rows tr")) {
    const selected = row.dataset.behaviorId === state.selectedBehaviorId;
    row.classList.toggle("is-selected", selected);
    row.querySelector(".behavior-button")?.setAttribute(
      "aria-expanded",
      String(selected),
    );
  }
}

function detailCard(title, body) {
  const card = element("section", "detail-card");
  card.append(element("h3", "", title));
  if (typeof body === "string") {
    card.append(element("p", "muted", body));
  } else {
    card.append(body);
  }
  return card;
}

function expandableDetailCard(title, body) {
  const card = element("details", "detail-card expandable-card");
  const summary = element("summary", "expandable-summary");
  summary.append(element("span", "expandable-title", title));
  summary.append(element("span", "expandable-toggle"));
  const content = element("div", "expandable-content");
  content.append(body);
  card.append(summary, content);
  return card;
}

function assessmentDetails(behavior) {
  const wrapper = element("div");
  wrapper.append(element("p", "muted", behavior.assessment.reason));
  if (!behavior.openQuestions.length) return wrapper;

  const questions = element("div", "assessment-questions");
  questions.append(element("h4", "", "Decision needed"));
  for (const question of behavior.openQuestions) {
    const item = element("article", "open-question");
    const heading = element("div", "open-question-heading");
    heading.append(element("strong", "", question.title));
    heading.append(element("span", "open-question-id", question.id));
    item.append(heading);
    item.append(element("p", "", question.prompt));
    questions.append(item);
  }
  wrapper.append(questions);
  return wrapper;
}

function implementationDetails(behavior) {
  const list = element("div");
  for (const anchor of behavior.implementation.anchors) {
    const item = element("div", "evidence-row");
    const requirement = anchor.required ? "required" : "supporting";
    item.append(element("strong", "", `${anchor.matched ? "✓" : "?"} ${requirement} ${anchor.kind}: `));
    item.append(document.createTextNode(anchor.value));
    for (const match of anchor.evidence) {
      const source = element(
        "div",
        "",
        `↳ ${match.graph} · ${match.sourceFile || "no source"}${match.sourceLocation ? `:${match.sourceLocation.replace(/^L/, "")}` : ""} · ${match.label}`,
      );
      item.append(source);
    }
    list.append(item);
  }
  return list;
}

function verificationDetails(behavior) {
  const wrapper = element("div", "proof-list");
  const boundary = element(
    "p",
    "muted",
    `Required: ${behavior.verification.requiredBoundaries.join(", ") || "none"}. ` +
      `Satisfied now: ${behavior.verification.satisfiedBoundaries.join(", ") || "none"}.`,
  );
  wrapper.append(boundary);
  for (const test of behavior.verification.tests) {
    const item = element("article", "proof-test");
    const heading = element("div", "proof-test-heading");
    heading.append(element("strong", "", test.title));
    heading.append(
      element(
        "span",
        "test-type",
        testTypeLabels[test.testType] || displayLabel(test.testType),
      ),
    );
    item.append(heading);
    const stateLine = element("div", "proof-test-state");
    stateLine.append(statusPill(test.state));
    stateLine.append(element("span", "muted", test.id));
    item.append(stateLine);
    item.append(element("code", "test-path", test.path));
    item.append(
      element(
        "p",
        "proof-test-meta",
        `Runs on: ${test.platforms.join(", ")}. Covers: ${test.boundaries.join(", ")}.`,
      ),
    );
    if (test.latestRun) {
      item.append(
        element(
          "p",
          "proof-test-meta",
          `run ${test.latestRun.revision.slice(0, 12)} · ${test.latestRun.target} · ${test.latestRun.recordedAt}`,
        ),
      );
    }
    wrapper.append(item);
  }
  return wrapper;
}

function openBehavior(behavior) {
  state.selectedBehaviorId = behavior.id;
  syncBehaviorSelection();
  document.querySelector("#details-id").textContent =
    `${behavior.id} · ${behavior.sourceRefs.join(" · ")}`;
  document.querySelector("#details-title").textContent = behavior.title;
  const content = document.querySelector("#details-content");
  content.replaceChildren(
    detailCard("Requirement", behavior.requirement),
    detailCard("Assessment", assessmentDetails(behavior)),
    expandableDetailCard(
      "Implementation evidence",
      implementationDetails(behavior),
    ),
    detailCard("Qualifying proof", verificationDetails(behavior)),
  );
  document.querySelector("#behavior-details").hidden = false;
  document.querySelector("#behavior-workspace").classList.add("has-selection");
}

function closeBehaviorDetails(restoreFocus = true) {
  const selectedId = state.selectedBehaviorId;
  state.selectedBehaviorId = null;
  document.querySelector("#behavior-details").hidden = true;
  document.querySelector("#behavior-workspace").classList.remove("has-selection");
  syncBehaviorSelection();
  if (!restoreFocus || !selectedId) return;
  const selectedRow = [...document.querySelectorAll("#behavior-rows tr")].find(
    (row) => row.dataset.behaviorId === selectedId,
  );
  selectedRow?.querySelector(".behavior-button")?.focus();
}

function installFilters() {
  document.querySelector("#behavior-search").addEventListener("input", (event) => {
    state.search = event.target.value.trim().toLocaleLowerCase();
    renderBehaviorRows();
  });
  document.querySelector("#assessment-filter").addEventListener("change", (event) => {
    state.assessment = event.target.value;
    renderBehaviorRows();
  });
  document.querySelector("#details-close").addEventListener("click", () => {
    closeBehaviorDetails();
  });
}

async function start() {
  try {
    const response = await fetch("./project-data/project-index.json", { cache: "no-store" });
    if (!response.ok) throw new Error(`project index returned ${response.status}`);
    state.data = await response.json();
    state.feature = state.data.features[0];
    if (!state.feature) throw new Error("project index has no features");
    renderProvenance();
    renderProjectSummary();
    renderFeatureHeader();
    populateFeatureSelect();
    populateAssessmentFilter();
    renderBehaviorRows();
    installFilters();
  } catch (error) {
    const badge = document.querySelector("#health-badge");
    badge.className = "health-badge warning";
    badge.textContent = "Project index unavailable";
    document.querySelector("main").prepend(
      detailCard(
        "Dashboard data could not be loaded",
        `${error.message}. Build the project index, then serve the repository over HTTP.`,
      ),
    );
  }
}

start();
