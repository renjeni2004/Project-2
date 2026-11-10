"""Draw the database ER diagram as a PNG (documentation visual)."""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

from config import VIZ_DIR

TABLES = {
    "regions":     (0.3, 7.0, ["region_id  PK", "region_name  UK"]),
    "customers":   (3.6, 7.0, ["customer_id  PK", "customer_name", "region_id  FK"]),
    "orders":      (7.0, 7.0, ["order_id  PK", "order_date", "customer_id  FK", "payment_method"]),
    "order_items": (10.4, 7.0, ["item_id  PK", "order_id  FK", "product_id  FK", "quantity", "unit_price",
                                "discount", "line_revenue  (generated)", "source_line_id  UK"]),
    "products":    (10.4, 2.3, ["product_id  PK", "product_name  UK", "category_id  FK", "list_price"]),
    "categories":  (6.6, 2.3, ["category_id  PK", "category_name  UK"]),
}
W, ROW = 2.9, 0.42


def box(ax, name, x, y, cols):
    h = ROW * (len(cols) + 1)
    ax.add_patch(FancyBboxPatch((x, y - h), W, h, boxstyle="round,pad=0.02", fc="#f8fafc", ec="#1f3864", lw=1.6))
    ax.add_patch(FancyBboxPatch((x, y - ROW), W, ROW, boxstyle="round,pad=0.02", fc="#1f3864", ec="#1f3864"))
    ax.text(x + W / 2, y - ROW / 2, name, color="white", ha="center", va="center", fontweight="bold")
    for i, c in enumerate(cols):
        ax.text(x + 0.12, y - ROW * (i + 1.5), c, va="center", fontsize=9,
                fontweight="bold" if "PK" in c else "normal")
    return (x, y - h, W, h)


def main():
    fig, ax = plt.subplots(figsize=(14, 7.6))
    ax.set_xlim(0, 14); ax.set_ylim(0, 7.5); ax.axis("off")
    pos = {n: box(ax, n, *v) for n, v in TABLES.items()}

    def link(a, b, label, side_a="right", side_b="left", ya=0.5, yb=0.5):
        xa, ya0, wa, ha = pos[a]; xb, yb0, wb, hb = pos[b]
        pa = (xa + (wa if side_a == "right" else 0), ya0 + ha * ya) if side_a in ("right", "left") else (xa + wa / 2, ya0 + (0 if side_a == "bottom" else ha))
        pb = (xb + (wb if side_b == "right" else 0), yb0 + hb * yb) if side_b in ("right", "left") else (xb + wb / 2, yb0 + (0 if side_b == "bottom" else hb))
        ax.annotate("", xy=pb, xytext=pa, arrowprops=dict(arrowstyle="->", color="#c0392b", lw=1.6))
        ax.text((pa[0] + pb[0]) / 2, (pa[1] + pb[1]) / 2 + 0.15, label, ha="center", fontsize=8, color="#c0392b")

    link("regions", "customers", "1 : N", ya=0.55, yb=0.55)
    link("customers", "orders", "1 : N", ya=0.55, yb=0.65)
    link("orders", "order_items", "1 : N", ya=0.6, yb=0.55)
    link("products", "order_items", "1 : N", side_a="top", side_b="bottom")
    link("categories", "products", "1 : N", ya=0.55, yb=0.55)
    ax.set_title("Sales BI Database - Entity Relationship Diagram (PostgreSQL)", fontsize=14, fontweight="bold", pad=12)
    fig.tight_layout(); fig.savefig(VIZ_DIR / "00_er_diagram.png", dpi=130); plt.close(fig)
    print("ER diagram saved")


if __name__ == "__main__":
    main()
