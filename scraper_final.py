#!/usr/bin/env python3
"""
Improved Google Images Scraper - Gets actual furniture images

Usage:
    python3 scraper.py --terms '["red couch", "oak table"]'
    python3 scraper.py --input terms.json
    python3 scraper.py --term "modern sofa"
"""

import argparse
import json
import sys
import time
import random
from typing import List, Dict, Any
from urllib.parse import quote_plus
import requests
from bs4 import BeautifulSoup
import re


class GoogleImageScraper:
    """Improved scraper that gets actual furniture images"""
    
    def __init__(self, delay_range=(1, 3)):
        self.delay_range = delay_range
        self.session = requests.Session()
        self.user_agents = [
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        ]
    
    def _get_headers(self):
        return {
            'User-Agent': random.choice(self.user_agents),
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.5',
            'Accept-Encoding': 'gzip, deflate, br',
            'DNT': '1',
            'Connection': 'keep-alive',
            'Upgrade-Insecure-Requests': '1',
        }
    
    def _delay(self):
        time.sleep(random.uniform(*self.delay_range))
    
    def _is_valid_image_url(self, url: str) -> bool:
        """Check if URL is likely a real product image"""
        if not url or len(url) < 20:
            return False
        
        # Skip Google UI elements
        skip_patterns = [
            'ssl.gstatic.com/gb/images/bar',  # Google bar icons
            'www.gstatic.com/images/branding',  # Google branding
            'www.google.com/images/branding',
            '/logos/',
            'logo.png',
            'icon.png',
            'favicon',
            'loading.gif',
            'placeholder',
        ]
        
        url_lower = url.lower()
        for pattern in skip_patterns:
            if pattern in url_lower:
                return False
        
        # Must be http/https
        if not url.startswith(('http://', 'https://')):
            return False
        
        # Check for image-like patterns
        has_image_indicator = any([
            '.jpg' in url_lower,
            '.jpeg' in url_lower,
            '.png' in url_lower,
            '.webp' in url_lower,
            'image' in url_lower,
            'img' in url_lower,
            'photo' in url_lower,
            'encrypted-tbn' in url_lower,  # Google's image cache
        ])
        
        return has_image_indicator
    
    def _extract_images_from_json(self, html: str) -> List[str]:
        """Extract image URLs from embedded JSON data in the page"""
        images = []
        
        # Google Images embeds data in JavaScript objects
        # Look for patterns like ["https://...",width,height]
        patterns = [
            r'"(https://encrypted-tbn\d\.gstatic\.com/images\?q=tbn:[^"]+)"',
            r'"(https://[^"]+\.(?:jpg|jpeg|png|webp)[^"]*)"',
            r'\["(https://[^"]+)",\d+,\d+\]',  # [url, width, height] format
        ]
        
        for pattern in patterns:
            matches = re.findall(pattern, html)
            for match in matches:
                # Clean up the URL
                url = match.replace('\\u003d', '=').replace('\\u0026', '&')
                if self._is_valid_image_url(url):
                    images.append(url)
        
        return images
    
    def get_image(self, search_term: str) -> Dict[str, Any]:
        """
        Search Google Images and get the FIRST valid image
        """
        # Use Google Images search
        url = f"https://www.google.com/search?q={quote_plus(search_term)}&tbm=isch&hl=en"
        
        print(f"  🔍 Searching images for: '{search_term}'", file=sys.stderr)
        
        try:
            response = self.session.get(url, headers=self._get_headers(), timeout=15)
            response.raise_for_status()
            
            product = {
                'title': search_term.title(),
                'price': 'N/A',
                'link': url,
                'image': '',
                'source': 'Google Images',
                'rating': None,
                'reviews': None,
                'search_term': search_term
            }
            
            # Get the HTML
            html = response.text
            soup = BeautifulSoup(html, 'html.parser')
            
            # Method 1: Extract from JSON-like structures in the page
            json_images = self._extract_images_from_json(html)
            if json_images:
                # Get the first valid one
                for img_url in json_images:
                    if len(img_url) > 50:  # Decent length URL
                        product['image'] = img_url
                        print(f"  ✅ Found image (JSON): {img_url[:80]}...", file=sys.stderr)
                        return product
            
            # Method 2: Look for img tags with actual images
            images = soup.find_all('img')
            for img in images:
                src = img.get('src', '') or img.get('data-src', '')
                
                if self._is_valid_image_url(src) and len(src) > 50:
                    product['image'] = src
                    print(f"  ✅ Found image (img tag): {src[:80]}...", file=sys.stderr)
                    return product
            
            # Method 3: Look in all 'a' tags for data attributes
            links = soup.find_all('a')
            for link in links:
                # Check all attributes for image URLs
                for attr, value in link.attrs.items():
                    if isinstance(value, str) and self._is_valid_image_url(value) and len(value) > 50:
                        product['image'] = value
                        print(f"  ✅ Found image (link attr): {value[:80]}...", file=sys.stderr)
                        return product
            
            # Method 4: Search for specific Google Images patterns in scripts
            scripts = soup.find_all('script')
            for script in scripts:
                script_text = script.string
                if script_text and 'encrypted-tbn' in script_text:
                    # Find all encrypted thumbnail URLs
                    matches = re.findall(r'https://encrypted-tbn\d\.gstatic\.com/images\?q=tbn:[A-Za-z0-9_-]+', script_text)
                    if matches:
                        product['image'] = matches[0]
                        print(f"  ✅ Found image (script): {matches[0][:80]}...", file=sys.stderr)
                        return product
            
            # Method 5: Last resort - look for ANY reasonable image URL in the page
            all_urls = re.findall(r'https://[^\s"\'<>]+\.(?:jpg|jpeg|png|webp)', html)
            for img_url in all_urls:
                if self._is_valid_image_url(img_url) and len(img_url) > 50:
                    product['image'] = img_url
                    print(f"  ✅ Found image (pattern): {img_url[:80]}...", file=sys.stderr)
                    return product
            
            print(f"  ⚠️  No valid image found for '{search_term}'", file=sys.stderr)
            return product
            
        except Exception as e:
            print(f"  ❌ Error: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc(file=sys.stderr)
            return {
                'title': search_term.title(),
                'price': 'N/A',
                'link': url,
                'image': '',
                'source': 'Search failed',
                'rating': None,
                'reviews': None,
                'search_term': search_term
            }
    
    def scrape_multiple(self, search_terms: List[str]) -> List[Dict[str, Any]]:
        """Scrape multiple images"""
        print(f"\n{'='*60}", file=sys.stderr)
        print(f"🖼️  Scraping images for {len(search_terms)} items", file=sys.stderr)
        print(f"{'='*60}\n", file=sys.stderr)
        
        results = []
        for idx, term in enumerate(search_terms, 1):
            print(f"[{idx}/{len(search_terms)}]", file=sys.stderr)
            product = self.get_image(term)
            results.append(product)
            
            if idx < len(search_terms):
                self._delay()
        
        images_found = len([r for r in results if r['image']])
        print(f"\n{'='*60}", file=sys.stderr)
        print(f"✅ Done! Found {images_found}/{len(search_terms)} images", file=sys.stderr)
        print(f"{'='*60}\n", file=sys.stderr)
        
        return results


def main():
    parser = argparse.ArgumentParser(description='Improved Google Images scraper for furniture')
    
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--term', help='Single search term')
    group.add_argument('--terms', help='JSON array of search terms')
    group.add_argument('--input', help='JSON file with search terms')
    
    parser.add_argument('--output', help='Output JSON file (default: stdout)')
    
    args = parser.parse_args()
    
    # Parse search terms
    search_terms = []
    if args.term:
        search_terms = [args.term]
    elif args.terms:
        try:
            search_terms = json.loads(args.terms)
        except json.JSONDecodeError as e:
            print(f"❌ Error parsing --terms JSON: {e}", file=sys.stderr)
            sys.exit(1)
    elif args.input:
        try:
            with open(args.input, 'r') as f:
                search_terms = json.load(f)
        except Exception as e:
            print(f"❌ Error reading input file: {e}", file=sys.stderr)
            sys.exit(1)
    
    if not search_terms or not isinstance(search_terms, list):
        print("❌ Invalid search terms", file=sys.stderr)
        sys.exit(1)
    
    # Run scraper
    scraper = GoogleImageScraper()
    
    try:
        results = scraper.scrape_multiple(search_terms)
        output_json = json.dumps(results, indent=2)
        
        if args.output:
            with open(args.output, 'w') as f:
                f.write(output_json)
            print(f"✅ Results written to {args.output}", file=sys.stderr)
        else:
            print(output_json)
        
        sys.exit(0)
        
    except KeyboardInterrupt:
        print("\n\n⚠️  Interrupted", file=sys.stderr)
        sys.exit(130)
    except Exception as e:
        print(f"\n❌ Fatal error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

