function handleMobileNav() {
  const mobileToggle = document.querySelector("[data-mobile-toggle]");
  const navigation = document.querySelector("[data-navigation]");

  if (!mobileToggle || !navigation) return;

  mobileToggle.addEventListener("click", () => {
    navigation.classList.toggle("open");
    mobileToggle.classList.toggle("active");
  });

  // Close menu when clicking outside
  document.documentElement.addEventListener("click", (event) => {
    if (!mobileToggle.contains(event.target) && !navigation.contains(event.target)) {
      navigation.classList.remove("open");
      mobileToggle.classList.remove("active");
    }
  });

  // Close menu when clicking a nav link
  navigation.querySelectorAll(".nav-link").forEach((link) => {
    link.addEventListener("click", (event) => {
      const href = link.getAttribute("href");

      // For anchor links, prevent default and handle manually
      if (href && href.startsWith("#")) {
        event.preventDefault();

        // Close menu first
        navigation.classList.remove("open");
        mobileToggle.classList.remove("active");

        // Then scroll to the target after a brief delay
        setTimeout(() => {
          const target = document.querySelector(href);
          if (target) {
            target.scrollIntoView({ behavior: "smooth" });
            // Update URL hash
            history.pushState(null, null, href);
          }
        }, 150);
      } else {
        // For external links, just close the menu
        navigation.classList.remove("open");
        mobileToggle.classList.remove("active");
      }
    });
  });
}

function handleThemeToggle() {
  const themeToggle = document.querySelector("[data-theme-toggle]");
  const html = document.documentElement;

  if (!themeToggle) return;

  // Check for saved theme preference or default to light
  const savedTheme = localStorage.getItem("theme");
  if (savedTheme) {
    html.className = savedTheme;
  } else if (window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches) {
    // Use system preference if no saved preference
    html.className = "theme-dark";
  }

  themeToggle.addEventListener("click", () => {
    const currentTheme = html.className;
    const newTheme = currentTheme === "theme-light" ? "theme-dark" : "theme-light";

    html.className = newTheme;
    localStorage.setItem("theme", newTheme);
  });

  // Listen for system theme changes
  window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", (e) => {
    // Only auto-switch if user hasn't manually set a preference
    if (!localStorage.getItem("theme")) {
      html.className = e.matches ? "theme-dark" : "theme-light";
    }
  });
}

function handleFlipCards() {
  const flipCards = document.querySelectorAll(".flip-card");

  // Check if touch device
  const isTouchDevice = () => {
    return (
      "ontouchstart" in window ||
      navigator.maxTouchPoints > 0 ||
      window.matchMedia("(max-width: 767px)").matches
    );
  };

  flipCards.forEach((card) => {
    // Set up scroll-to-flip on mobile
    if (isTouchDevice()) {
      const observer = new IntersectionObserver(
        (entries) => {
          entries.forEach((entry) => {
            if (entry.isIntersecting) {
              // Card is in the "flip zone" - flip it
              card.classList.add("flipped");
            } else {
              // Card left the flip zone - flip back
              card.classList.remove("flipped");
            }
          });
        },
        {
          // Trigger when card is in the middle 40% of the viewport
          rootMargin: "-30% 0px -30% 0px",
          threshold: 0.5
        }
      );

      observer.observe(card);
    }

    card.addEventListener("click", (event) => {
      // Only handle taps on mobile/touch devices
      if (!isTouchDevice()) return;

      // Don't flip back if clicking the docs link when flipped
      const isFlipped = card.classList.contains("flipped");
      const clickedDocsLink = event.target.closest(".docs-link");

      if (isFlipped && clickedDocsLink) {
        // Let the link work normally
        return;
      }

      // Toggle the flip
      card.classList.toggle("flipped");
    });

    // Also handle keyboard for accessibility
    card.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        card.classList.toggle("flipped");
      }
    });
  });
}

// Initialize when DOM is ready
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", () => {
    handleMobileNav();
    handleThemeToggle();
    handleFlipCards();
  });
} else {
  // DOM already loaded, run immediately
  handleMobileNav();
  handleThemeToggle();
  handleFlipCards();
}
