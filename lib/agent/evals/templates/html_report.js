document.querySelectorAll("table.sortable").forEach((table) => {
  const headers = Array.from(table.querySelectorAll("thead th"));
  const body = table.tBodies[0];

  headers.forEach((header, index) => {
    header.tabIndex = 0;
    header.setAttribute("aria-sort", "none");

    const sort = () => {
      const ascending = header.dataset.direction !== "ascending";

      headers.forEach((item) => {
        item.dataset.direction = "";
        item.setAttribute("aria-sort", "none");
      });

      header.dataset.direction = ascending ? "ascending" : "descending";
      header.setAttribute("aria-sort", header.dataset.direction);

      const rows = Array.from(body.rows);
      rows.sort((left, right) => {
        const first = left.cells[index]?.textContent.trim() ?? "";
        const second = right.cells[index]?.textContent.trim() ?? "";
        const number = (value) => {
          const normalized = value.replace(/[,$%]/g, "");
          return /^-?\d+(?:\.\d+)?$/.test(normalized) ? Number(normalized) : null;
        };
        const firstNumber = number(first);
        const secondNumber = number(second);
        const comparison = firstNumber !== null && secondNumber !== null
          ? firstNumber - secondNumber
          : first.localeCompare(second, undefined, { numeric: true, sensitivity: "base" });

        return ascending ? comparison : -comparison;
      });

      rows.forEach((row) => body.append(row));
    };

    header.addEventListener("click", sort);
    header.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        sort();
      }
    });
  });
});
