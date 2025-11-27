// product-editor.js
(function () {
  let currentProduct = null;
  let universe = null; // conterrà window.TheLightUniverse quando pronto

  function parseNumber(input) {
    const v = parseFloat((input.value || "").replace(",", "."));
    return isFinite(v) ? v : 0;
  }

  function formatPrice(v) {
    if (!isFinite(v)) return "";
    return v.toFixed(2) + " €";
  }

  function initProductEditor() {
    // recupero oggetti globali
    universe = window.TheLightUniverse;
    if (!universe) {
      console.warn("TheLightUniverse non disponibile anche dopo il wait, editor non inizializzato");
      return;
    }

    const { showToast, BASE_URL, getCurrentProduct, getCurrentUser } = universe;

    const sheet = document.getElementById("sheet-product-editor");
    if (!sheet) {
      console.warn("sheet-product-editor non trovato");
      return;
    }

    const skuInput = document.getElementById("prod-sku");
    const nameInput = document.getElementById("prod-name");
    const imageHdInput = document.getElementById("prod-image-hd");
    const imageThumbInput = document.getElementById("prod-image-thumb");
    const galleryInput = document.getElementById("prod-gallery");
    const descHtmlInput = document.getElementById("prod-desc-html");
    const descPreview = document.getElementById("prod-desc-preview");

    const basePriceInput = document.getElementById("prod-base-price");
    const unitInput = document.getElementById("prod-unit");
    const markupRiv10Input = document.getElementById("prod-markup-riv10");
    const markupRivInput = document.getElementById("prod-markup-riv");
    const markupDistInput = document.getElementById("prod-markup-dist");

    const priceRiv10Output = document.getElementById("prod-price-riv10");
    const priceRivOutput = document.getElementById("prod-price-riv");
    const priceDistOutput = document.getElementById("prod-price-dist");

    const btnCancel = document.getElementById("btn-prod-cancel");
    const btnSave = document.getElementById("btn-prod-save");
    const btnEditProduct = document.getElementById("btn-edit-product");

    function updatePreview() {
      const html = descHtmlInput.value || "";
      descPreview.innerHTML = html;
    }

    function recalcPrices() {
      const base = parseNumber(basePriceInput);
      const mRiv10 = parseNumber(markupRiv10Input);
      const mRiv = parseNumber(markupRivInput);
      const mDist = parseNumber(markupDistInput);

      const pRiv10 = base * (1 + mRiv10 / 100);
      const pRiv = base * (1 + mRiv / 100);
      const pDist = base * (1 + mDist / 100);

      priceRiv10Output.value = base ? formatPrice(pRiv10) : "";
      priceRivOutput.value = base ? formatPrice(pRiv) : "";
      priceDistOutput.value = base ? formatPrice(pDist) : "";
    }

    function openEditor() {
      const user = getCurrentUser();
      if (!user || user.name !== "GOD ADMIN") {
        showToast("Solo GOD ADMIN può modificare le schede.", false);
        return;
      }

      const prod = getCurrentProduct();
      if (!prod) {
        showToast("Seleziona un prodotto nella galassia.", false);
        return;
      }
      currentProduct = prod;

      // Prefill campi
      skuInput.value = prod.sku || "";
      nameInput.value = prod.name || "";
      imageHdInput.value = prod.image_hd || prod.image || "";
      imageThumbInput.value = prod.image_thumb || "";
      galleryInput.value = (prod.gallery || []).join("\n");
      descHtmlInput.value = prod.description_html || "";
      updatePreview();

      const pricing = prod.pricing || {};
      basePriceInput.value =
        pricing.base_price != null ? pricing.base_price : "";
      unitInput.value = pricing.unit || "";

      markupRiv10Input.value =
        pricing.markup_riv10 != null ? pricing.markup_riv10 : 10;
      markupRivInput.value =
        pricing.markup_riv != null ? pricing.markup_riv : 20;
      markupDistInput.value =
        pricing.markup_dist != null ? pricing.markup_dist : 0;

      recalcPrices();
      sheet.style.display = "flex";
    }

    function closeEditor() {
      sheet.style.display = "none";
      currentProduct = null;
    }

    async function saveProduct() {
      if (!currentProduct) return;

      const user = getCurrentUser();
      if (!user || user.name !== "GOD ADMIN") {
        showToast("Solo GOD ADMIN può salvare le modifiche.", false);
        return;
      }

      const basePrice = parseNumber(basePriceInput);
      const mRiv10 = parseNumber(markupRiv10Input);
      const mRiv = parseNumber(markupRivInput);
      const mDist = parseNumber(markupDistInput);

      const pRiv10 = basePrice * (1 + mRiv10 / 100);
      const pRiv = basePrice * (1 + mRiv / 100);
      const pDist = basePrice * (1 + mDist / 100);

      // Aggiorno oggetto locale
      currentProduct.name = nameInput.value.trim() || currentProduct.name;
      currentProduct.image_hd = imageHdInput.value.trim();
      currentProduct.image_thumb = imageThumbInput.value.trim();
      currentProduct.gallery = (galleryInput.value || "")
        .split("\n")
        .map((v) => v.trim())
        .filter(Boolean);
      currentProduct.description_html = descHtmlInput.value;

      currentProduct.pricing = {
        base_price: basePrice,
        unit: unitInput.value.trim(),
        markup_riv10: mRiv10,
        markup_riv: mRiv,
        markup_dist: mDist,
        prices: {
          rivenditore10: pRiv10,
          rivenditore: pRiv,
          distributore: pDist,
        },
      };

      const payload = {
        sku: currentProduct.sku,
        name: currentProduct.name,
        image_hd: currentProduct.image_hd,
        image_thumb: currentProduct.image_thumb,
        gallery: currentProduct.gallery,
        description_html: currentProduct.description_html,
        pricing: currentProduct.pricing,
      };

      try {
        await fetch(BASE_URL + "/ecom/product/update", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });
        showToast("Scheda prodotto aggiornata.");
      } catch (e) {
        showToast(
          "Scheda aggiornata in locale. Backend non raggiungibile.",
          false
        );
      }

      closeEditor();
    }

    // === EVENTI ===
    if (btnEditProduct) {
      btnEditProduct.addEventListener("click", openEditor);
    } else {
      console.warn("btn-edit-product non trovato");
    }

    btnCancel.addEventListener("click", closeEditor);
    btnSave.addEventListener("click", saveProduct);

    descHtmlInput.addEventListener("input", updatePreview);
    [basePriceInput, markupRiv10Input, markupRivInput, markupDistInput].forEach(
      (el) => {
        el.addEventListener("input", recalcPrices);
      }
    );

    // esposizione per debug da console e per aggancio manuale
    universe.openProductEditor = openEditor;
  }

  // === QUI IL FIX IMPORTANTE ===
  function waitForUniverse(retries) {
    if (window.TheLightUniverse) {
      initProductEditor();
      return;
    }
    if (retries <= 0) {
      console.warn("TheLightUniverse non pronto dopo il timeout.");
      return;
    }
    setTimeout(() => waitForUniverse(retries - 1), 100);
  }

  // avvio dopo che il DOM è pronto, ma aspetto anche TheLightUniverse
  function start() {
    waitForUniverse(50); // max ~5 secondi
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }
})();