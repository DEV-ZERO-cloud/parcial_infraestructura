(function () {
  "use strict";
  var KEY = "horus-tracker-v1";
  var LABEL = { todo: "Pendiente", reading: "Leyendo", read: "Leído" };
  var state = load();
  var filter = "all";
  var query = "";

  function load() {
    try {
      var s = JSON.parse(localStorage.getItem(KEY));
      if (s && s.status && Array.isArray(s.custom)) return s;
    } catch (e) { /* sin almacenamiento: se trabaja en memoria */ }
    return { status: {}, dates: {}, custom: [] };
  }
  function save() { try { localStorage.setItem(KEY, JSON.stringify(state)); } catch (e) { /* ignorar */ } }

  function books() {
    var extra = state.custom.map(function (c, i) {
      return { id: c.id, n: HORUS_BOOKS.length + i + 1, title: c.title, author: c.author, anthology: false, custom: true };
    });
    return HORUS_BOOKS.concat(extra);
  }
  function st(b) { return state.status[b.id] || "todo"; }

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  function setStatus(id, v) {
    if (v === "todo") { delete state.status[id]; delete state.dates[id]; }
    else {
      state.status[id] = v;
      if (v === "read") state.dates[id] = new Date().toISOString().slice(0, 10);
      else delete state.dates[id];
    }
    save(); render();
  }

  function fmtDate(iso) {
    var p = iso.split("-");
    return p[2] + "/" + p[1] + "/" + p[0];
  }

  function renderShelf(all) {
    var shelf = document.getElementById("shelf");
    shelf.replaceChildren();
    all.forEach(function (b) {
      var li = el("li");
      var s = st(b);
      var btn = el("button", "spine");
      btn.type = "button";
      btn.dataset.s = s;
      btn.style.height = (56 + ((b.n * 7919) % 41)) + "px";
      if (s === "reading") btn.style.height = "96px";
      btn.setAttribute("aria-label", b.n + ". " + b.title + ": " + LABEL[s]);
      btn.title = b.n + ". " + b.title + " (" + LABEL[s] + ")";
      btn.addEventListener("click", function () { jump(b.id); });
      li.appendChild(btn);
      shelf.appendChild(li);
    });
  }

  function jump(id) {
    filter = "all"; query = ""; document.getElementById("q").value = "";
    render();
    var row = document.getElementById(id);
    if (row) {
      row.scrollIntoView({ block: "center" });
      row.classList.add("flash");
      setTimeout(function () { row.classList.remove("flash"); }, 1600);
    }
  }

  function renderNext(all) {
    var box = document.getElementById("next");
    box.replaceChildren();
    box.className = "next";
    var current = all.filter(function (b) { return st(b) === "reading"; })[0];
    var next = current || all.filter(function (b) { return st(b) === "todo"; })[0];
    if (!next) {
      box.classList.add("done");
      box.appendChild(el("h2", null, "Serie completa"));
      box.appendChild(el("p", "title", "Terminaste la Herejía"));
      box.appendChild(el("p", "meta", "Puedes agregar más libros abajo."));
      return;
    }
    box.appendChild(el("h2", null, current ? "Estás leyendo" : "Sigue en tu lista"));
    box.appendChild(el("p", "title", next.n + ". " + next.title));
    box.appendChild(el("p", "meta", next.author));
    var btn = el("button", "primary", current ? "Marcar como leído" : "Empezar a leer");
    btn.type = "button";
    btn.addEventListener("click", function () { setStatus(next.id, current ? "read" : "reading"); });
    box.appendChild(btn);
  }

  function renderBooks(all) {
    var list = document.getElementById("books");
    list.replaceChildren();
    var q = query.trim().toLowerCase();
    var shown = all.filter(function (b) {
      if (filter !== "all" && st(b) !== filter) return false;
      return !q || (b.title + " " + b.author).toLowerCase().indexOf(q) !== -1;
    });
    shown.forEach(function (b) {
      var s = st(b);
      var li = el("li", "book");
      li.id = b.id; li.dataset.s = s;
      li.appendChild(el("span", "n", String(b.n)));

      var info = el("div");
      var h = el("h3", null, b.title);
      if (b.anthology) h.appendChild(el("span", "tag", "antología"));
      info.appendChild(h);
      var by = el("p", "by", b.author || "Autor sin indicar");
      if (s === "read" && state.dates[b.id]) by.appendChild(el("span", "when", "Leído el " + fmtDate(state.dates[b.id])));
      if (b.custom) {
        var rm = el("button", "remove", "Quitar");
        rm.type = "button";
        rm.addEventListener("click", function () {
          state.custom = state.custom.filter(function (c) { return c.id !== b.id; });
          delete state.status[b.id]; delete state.dates[b.id];
          save(); render();
        });
        by.appendChild(rm);
      }
      info.appendChild(by);
      li.appendChild(info);

      var seg = el("div", "seg");
      seg.setAttribute("role", "group");
      seg.setAttribute("aria-label", "Estado de " + b.title);
      ["todo", "reading", "read"].forEach(function (v) {
        var btn = el("button", null, LABEL[v]);
        btn.type = "button"; btn.dataset.v = v;
        btn.setAttribute("aria-pressed", String(s === v));
        btn.addEventListener("click", function () { setStatus(b.id, v); });
        seg.appendChild(btn);
      });
      li.appendChild(seg);
      list.appendChild(li);
    });
    document.getElementById("empty").hidden = shown.length > 0;
  }

  function render() {
    var all = books();
    var read = all.filter(function (b) { return st(b) === "read"; }).length;
    document.getElementById("countRead").textContent = read;
    document.getElementById("countTotal").textContent = all.length;
    document.getElementById("tallyLabel").textContent = read === 1 ? "libro leído" : "libros leídos";
    renderShelf(all); renderNext(all); renderBooks(all);
  }

  document.getElementById("filters").addEventListener("click", function (e) {
    var f = e.target.dataset && e.target.dataset.f;
    if (!f) return;
    filter = f;
    Array.prototype.forEach.call(this.children, function (b) { b.setAttribute("aria-pressed", String(b.dataset.f === f)); });
    renderBooks(books());
  });
  document.getElementById("q").addEventListener("input", function () { query = this.value; renderBooks(books()); });
  document.getElementById("addForm").addEventListener("submit", function (e) {
    e.preventDefault();
    var title = this.elements.title.value.trim();
    if (!title) return;
    state.custom.push({ id: "c" + Date.now(), title: title, author: this.elements.author.value.trim() });
    save(); this.reset(); render();
  });
  document.getElementById("reset").addEventListener("click", function () {
    if (confirm("Se borrará todo tu progreso y los libros que agregaste. ¿Continuar?")) {
      state = { status: {}, dates: {}, custom: [] }; save(); render();
    }
  });

  fetch("/health").then(function (r) { return r.json(); }).then(function (h) {
    document.getElementById("build").textContent = "Versión " + h.version + " · commit " + String(h.commit).slice(0, 7);
  }).catch(function () {});

  render();
})();
