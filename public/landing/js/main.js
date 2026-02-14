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

// Initialize when DOM is ready
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", handleMobileNav);
} else {
  // DOM already loaded, run immediately
  handleMobileNav();
}
