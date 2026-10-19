(function () {
  "use strict";
  var cfg = window.HOLA_CONFIG || {};

  document.documentElement.classList.remove("no-js");

  var year = document.querySelector("[data-year]");
  if (year) year.textContent = String(new Date().getFullYear());

  // Mark the current page in the navigation.
  var path = location.pathname.replace(/\/+$/, "") || "/";
  document.querySelectorAll(".site-nav li a, .utility-links a").forEach(function (a) {
    var href = a.getAttribute("href").replace(/\/+$/, "") || "/";
    if (href === path) a.setAttribute("aria-current", "page");
  });

  // Mobile menu.
  var toggle = document.querySelector(".nav-toggle");
  var nav = document.getElementById("site-nav");
  if (toggle && nav) {
    toggle.addEventListener("click", function () {
      var open = nav.classList.toggle("open");
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && nav.classList.contains("open")) {
        nav.classList.remove("open");
        toggle.setAttribute("aria-expanded", "false");
        toggle.focus();
      }
    });
  }

  // Links that point at the app.
  document.querySelectorAll("[data-app-link]").forEach(function (a) {
    a.setAttribute("href", cfg.appUrl || "/app");
  });

  // Enquiry forms (employer registration and contact).
  document.querySelectorAll("form[data-enquiry]").forEach(function (form) {
    var status = form.querySelector(".form-status");
    var button = form.querySelector("button[type=submit]");

    function show(kind, message) {
      status.className = "form-status show " + kind;
      status.textContent = message;
      status.setAttribute("tabindex", "-1");
      status.focus();
    }

    form.addEventListener("submit", function (event) {
      event.preventDefault();
      if (!form.reportValidity()) return;
      if (!cfg.enquiryEndpoint) {
        show("warn", "Online submission is not switched on yet, so nothing was sent. Please try again later.");
        return;
      }

      var data = { type: form.getAttribute("data-enquiry") };
      new FormData(form).forEach(function (value, key) {
        data[key] = value;
      });
      data.consent = form.elements.consent ? form.elements.consent.checked : undefined;

      button.disabled = true;
      var original = button.textContent;
      button.textContent = "Sending…";
      status.className = "form-status";

      fetch(cfg.enquiryEndpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(data),
      })
        .then(function (res) {
          return res.json().catch(function () { return {}; }).then(function (body) { return { res: res, body: body }; });
        })
        .then(function (r) {
          if (r.res.ok && r.body.ok) {
            form.reset();
            show("ok", "Thank you. Your " + (data.type === "contact" ? "message" : "request") + " has been received" + (r.body.reference ? " (reference " + r.body.reference + ")" : "") + ". We will reply by email.");
          } else if (r.res.status === 400 && r.body.error) {
            show("err", r.body.error);
          } else if (r.res.status === 429) {
            show("err", "Too many submissions from your connection. Please try again in an hour.");
          } else {
            show("err", "We could not send this right now, and nothing was received. Please try again later.");
          }
        })
        .catch(function () {
          show("err", "We could not reach the service, and nothing was received. Check your connection and try again.");
        })
        .then(function () {
          button.disabled = false;
          button.textContent = original;
        });
    });
  });
})();
