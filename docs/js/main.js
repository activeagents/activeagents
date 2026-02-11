function handleMobileNav() {
  const mobileToggle = document.querySelector("[data-mobile-toggle]");
  const navigation = document.querySelector("[data-navigation]");

  mobileToggle.addEventListener("click", () => {
    navigation.classList.toggle("open");
    mobileToggle.classList.toggle("active");
  });

  document.documentElement.addEventListener("click", (event) => {
    if (!mobileToggle.contains(event.target) && !navigation.contains(event.target)) {
      navigation.classList.remove("open");
      mobileToggle.classList.remove("active");
    }
  });
}

function handleFlipCards() {
  const flipCards = document.querySelectorAll(".flip-card");

  flipCards.forEach((card) => {
    card.addEventListener("click", () => {
      // On mobile, toggle the flipped state
      card.classList.toggle("flipped");
    });

    // Also handle keyboard accessibility
    card.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        card.classList.toggle("flipped");
      }
    });
  });

  // Click outside to close flipped cards on mobile
  document.addEventListener("click", (event) => {
    if (!event.target.closest(".flip-card")) {
      flipCards.forEach((card) => card.classList.remove("flipped"));
    }
  });
}

document.addEventListener("DOMContentLoaded", () => {
  handleMobileNav();
  handleFlipCards();
});
