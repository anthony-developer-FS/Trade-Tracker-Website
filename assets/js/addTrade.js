document.addEventListener("DOMContentLoaded", function () {
    // 1. Trade Info
  let tickerInput = document.getElementById("symbol");
  let saveTradeBtn = document.querySelector(".btn--lg");
  //   Plan and risk inputs
  let stopPriceInput = document.getElementById("stop-price");
  let targetPriceInput = document.getElementById("target-price");
  let plannedRiskInput = document.getElementById("planned-risk");    
  // organize
  let tagInput = document.getElementById("tag-input");
  let tags = [document.getElementById("starter").textContent];
  let chipInput = document.querySelector("[data-chip-input]");
  let suggestions = document.querySelector("[data-tag-suggestions]");
  let setupInput = document.getElementById("setup");

  function tradeData() {
    let data = {
      ticker: tickerInput.value,
      direction: document.querySelector("[name='direction']:checked").value,
      side: document.getElementById("fill-0-side").value,
      date: document.getElementById("fill-0-time").value,
      shares: document.getElementById("fill-0-qty").value,
      price: document.getElementById("fill-0-price").value,
      fees: document.getElementById("fill-0-fees").value,
    };
    return data;
  }

  function optionalData() {
    let optData = {
      stopPrice: stopPriceInput.value,
      targetPrice: targetPriceInput.value,
      plannedRisk: plannedRiskInput.value,
    };
    return optData;
  }

  function notesAndOrganizeData() {
    let notes = {
        stars
        setup: setupInput.value,
        tags: tags,
        lists: [...document.querySelectorAll("[name='trade_list_ids[]']:checked")].map((box) => box.value),
        notes: document.getElementById("notes").value,
        screenshots: document.getElementById("screenshots").files
    }
    return notes;
  }

  tagInput.addEventListener("keydown", function (event) {
    if (event.key === "Enter") {
      event.preventDefault();
      addTag(tagInput.value);
      tagInput.value = "";
    }
  });

  //creating chips and displaying to user in tag input box
    function createChip(name) {
      let chip = document.createElement("span");
      chip.className = "chip";
      chip.textContent = name;
      
      let remove = document.createElement("button");
      remove.type = "button";
      remove.className = "chip__remove";
      remove.setAttribute("aria-label", `Remove tag ${name}`);
      remove.innerHTML = '<svg width="12" height="12" viewBox="0 0 12 12" fill="none" aria-hidden="true"><path d="M3 3l6 6M9 3L3 9" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>';
      remove.addEventListener("click", function () {
        tags = tags.filter((tag) => tag !== name);
        chip.remove();
      });

      let starter = document.getElementById("starter");
      starter.querySelector(".chip__remove").addEventListener("click", function () {
        tags = tags.filter((tag) => tag !== starter.textContent);
        starter.remove();
      });

      chip.appendChild(remove);
      chipInput.insertBefore(chip, tagInput);
    }

  // adding chip inputs to tags when clicked and changing its styling
  suggestions.addEventListener("click", function (event) {
    let button = event.target.closest(".chip-suggestion");
    if (!button) return;
    addTag(button.textContent.replace(/^\+\s*/, ""));
    button.remove();
  });

  function addTag(name) {
    name = name.trim();
    if (!name || tags.includes(name)) return;
    tags.push(name);
    createChip(name);
  }

  saveTradeBtn.addEventListener("click", function (event) {
    event.preventDefault();
    console.log(tradeData());
    console.log(optionalData());
    console.log(notesAndOrganizeData());
    console.log(tags);
  });
});
