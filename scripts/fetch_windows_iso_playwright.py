#!/usr/bin/env python3
import argparse
import sys
import time
from playwright.sync_api import sync_playwright


def dismiss_overlays(page) -> None:
    candidates = [
        page.get_by_role("button", name="Accept"),
        page.get_by_role("button", name="Accept all"),
        page.get_by_role("button", name="I agree"),
        page.get_by_role("button", name="Agree"),
    ]
    for locator in candidates:
        try:
            if locator.first.is_visible(timeout=2000):
                locator.first.click()
                page.wait_for_timeout(1000)
                return
        except Exception:
            continue


def select_controls(page):
    deadline = time.time() + 120
    while time.time() < deadline:
        select = page.locator("select").filter(has=page.locator("option"))
        count = select.count()
        controls = []
        for idx in range(count):
            locator = select.nth(idx)
            option_data = locator.locator("option").evaluate_all(
                "(nodes) => nodes.map((node) => ({label: node.textContent || '', value: node.value || ''}))"
            )
            meaningful = [
                option for option in option_data
                if option["value"]
                and option["value"].lower() != "null"
                and "select" not in option["label"].strip().lower()
            ]
            if meaningful:
                controls.append((locator, meaningful))
        if controls:
            return controls
        page.wait_for_timeout(1000)
    raise TimeoutError("Timed out waiting for populated download selectors")


def choose_option(page, label: str, value_fragment: str):
    controls = select_controls(page)
    for locator, option_data in controls:
        for option in option_data:
            if value_fragment.lower() in option["label"].lower():
                locator.select_option(value=option["value"])
                return locator
            if label.lower() == option["label"].strip().lower():
                locator.select_option(value=option["value"])
                return locator
    raise RuntimeError(f"Could not find select option: {label}")


def click_confirm_for_select(select_locator, page) -> None:
    ancestors = [
        "xpath=ancestor::section[1]",
        "xpath=ancestor::form[1]",
        "xpath=ancestor::div[contains(@class, 'form')][1]",
        "xpath=ancestor::div[1]",
    ]
    for ancestor in ancestors:
        try:
            button = select_locator.locator(f"{ancestor}").get_by_role("button", name="Confirm").first
            if button.is_visible(timeout=3000):
                button.click(timeout=30000)
                page.wait_for_load_state("domcontentloaded")
                page.wait_for_timeout(1500)
                return
        except Exception:
            continue

    buttons = page.get_by_role("button", name="Confirm")
    buttons.first.click(timeout=30000)
    page.wait_for_load_state("domcontentloaded")
    page.wait_for_timeout(1500)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--page", required=True)
    parser.add_argument("--edition", required=True)
    parser.add_argument("--language", required=True)
    args = parser.parse_args()

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        page = browser.new_page()
        page.goto(args.page, wait_until="domcontentloaded", timeout=120000)
        dismiss_overlays(page)

        edition_select = choose_option(page, args.edition, "Windows 11")
        click_confirm_for_select(edition_select, page)
        language_select = choose_option(page, args.language, args.language)
        click_confirm_for_select(language_select, page)

        page.wait_for_selector('a[href*="software-download.microsoft.com"]', timeout=120000)
        hrefs = page.locator('a[href*="software-download.microsoft.com"]').evaluate_all(
            "(nodes) => nodes.map((node) => node.href)"
        )
        for href in hrefs:
            if href.lower().endswith(".iso"):
                sys.stdout.write(href)
                browser.close()
                return 0

        browser.close()
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
