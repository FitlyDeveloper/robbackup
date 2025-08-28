import time
import random
import csv
import os
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.common.action_chains import ActionChains
from selenium.webdriver.firefox.options import Options
from selenium.common.exceptions import TimeoutException, NoSuchElementException
import threading
import sys
import select
import keyboard

class SolpumpBot:
    def __init__(self):
        """Initialize the bot with Firefox driver"""
        self.driver = None
        self.base_bet = 0.001
        self.current_bet = 0.001
        self.max_bet = 0.128
        self.betting_active = False
        self.cashout_target = 1.25
        self.progressive_set_to = 90
        self.advanced_betting_on = False
        self.round_prepped = False
        self.player_account_name = "6-7x"  # this is the visible account label on Solpump
        self.current_multiplier = 0.0
        self.setup_driver()
        
    # --- Helpers for multiplier logging ---
    def _read_center_multiplier(self) -> float:
        try:
            # FOCUS ON CENTER GAME AREA ONLY - ignore top bar completely
            mult = self.driver.execute_script("""
                return (function(){
                  // Check if countdown is active first
                  if(window.roundCountdownSeconds !== null && window.roundCountdownSeconds !== undefined) {
                    return 0; // Don't read during countdown
                  }
                  
                  function readAt(x,y){
                    var els = document.elementsFromPoint(x,y)||[];
                    for(var i=0;i<els.length;i++){
                      var el = els[i];
                      var t=(el.textContent||'').trim();
                      
                      // Skip elements that are likely from top bar (small font, positioned high)
                      var rect = el.getBoundingClientRect();
                      if(rect.top < window.innerHeight * 0.25) continue; // Skip top 25% of screen
                      
                      // More flexible multiplier matching
                      var m=t.match(/(\\d+(?:\\.\\d{1,2})?)x/i);
                      if(m){ 
                        var v=parseFloat(m[1]); 
                        if(v>=1.00&&v<=10000) {
                          // Accept if element is reasonably large OR in center area
                          var fontSize = parseFloat(getComputedStyle(el).fontSize) || 0;
                          var centerDistance = Math.abs(rect.left + rect.width/2 - window.innerWidth/2);
                          if(fontSize >= 16 || centerDistance < 200) { // Lower font requirement or center position
                            return v;
                          }
                        }
                      }
                    }
                    return 0;
                  }
                  
                  var w=window.innerWidth, h=window.innerHeight; 
                  var cx=w/2, cy=h*0.45; // Slightly higher center
                  var offs=[-100,-60,-30,0,30,60,100]; // Wider search area
                  var best=0;
                  for(var i=0;i<offs.length;i++){
                    var v=readAt(cx, cy+offs[i]); 
                    if(v>best) best=v;
                  }
                  
                  // Also try window tracker as backup
                  if(best === 0) {
                    try {
                      var trackerMult = window.currentMultiplier || 0;
                      if(trackerMult > 0) best = trackerMult;
                    } catch(e) {}
                  }
                  
                  return best;
                })();
            """)
            if mult and float(mult) > 0:
                return float(mult)
        except Exception:
            pass
        return 0.0

    def _log_multiplier_tick(self, last_mult: float) -> float:
        # Check if countdown is active first
        try:
            countdown_active = self.driver.execute_script("return window.roundCountdownSeconds !== null && window.roundCountdownSeconds !== undefined;")
            if countdown_active:
                return last_mult  # Don't read or log during countdown
        except Exception:
            pass
            
        cur = self._read_center_multiplier()
        # Only log if significant change AND not stale data
        if cur > 0 and abs(cur - last_mult) > 0.01:  # Require bigger change to reduce spam
            # Don't log if multiplier seems stale (same for too long)
            if not hasattr(self, '_same_mult_count'):
                self._same_mult_count = 0
            if abs(cur - last_mult) < 0.005:
                self._same_mult_count += 1
            else:
                self._same_mult_count = 0
            
            # Only log if not spamming same value
            if self._same_mult_count < 10:  # Max 10 same values before stopping logs
                print(f"📈 {cur:.2f}x")
            return cur
        return last_mult

    def setup_driver(self):
        """Setup Firefox driver"""
        options = Options()
        options.set_preference("media.volume_scale", "0.0")
        
        self.driver = webdriver.Firefox(options=options)
        self.driver.maximize_window()
    
    def navigate_to_solpump(self):
        """Navigate to Solpump website"""
        print("🌐 Navigating to Solpump...")
        self.driver.get("https://solpump.com")
        time.sleep(5)
        print("✅ Solpump loaded")
    
    def wait_for_user_login(self):
        """Wait for user to manually login"""
        print("\n⚠️  Login to Solpump first!")
        input("Press Enter when logged in...")
        
    def load_historical_results(self, filename="solpump_results.csv"):
        """Load historical results from CSV file"""
        results = []
        if os.path.exists(filename):
            with open(filename, 'r') as f:
                reader = csv.reader(f)
                next(reader, None)  # Skip header
                for row in reader:
                    if len(row) >= 2:
                        try:
                            results.append(float(row[1]))
                        except:
                            pass
        print(f"📊 Loaded {len(results)} historical results")
        return results
        
    def wait_for_betting_window(self):
        """Wait for the betting window to open - no timeout, only based on multiplier activity"""
        print("⏳ Waiting for betting window...")
        self.round_prepped = False
        
        # Clear Python-side tracking
        if hasattr(self, '_same_mult_count'):
            self._same_mult_count = 0
        if hasattr(self, '_last_countdown'):
            delattr(self, '_last_countdown')
        
        # Let the page naturally transition to betting phase
        
        last_logged_countdown = None
        last_mult = 0.0
        start_time = time.time()
        max_wait_time = 120  # 2 minute timeout to prevent infinite waiting
        found_countdown = False
        
        # Wait a moment for page to settle after round end
        time.sleep(2)  # Increased wait time for better state clearing
        
        while True:
            try:
                # Check for timeout
                if time.time() - start_time > max_wait_time:
                    print(f"⚠️ Betting window timeout after {max_wait_time}s - forcing continuation")
                    return True
                
                # Always log multiplier ticks
                last_mult = self._log_multiplier_tick(last_mult)
                
                # Check countdown state - with better error handling
                try:
                    js = self.driver.execute_script(
                        "return {c:(typeof window.roundCountdownSeconds==='number'?window.roundCountdownSeconds:null), a:!!window.isGameActive};"
                    )
                    countdown_value = js.get('c', None)
                    is_active = bool(js.get('a', False))
                except Exception:
                    countdown_value = None
                    is_active = False
                
                # Also check for countdown in page text as primary method
                try:
                    page_text = self.driver.page_source.lower()
                    # Look for countdown patterns in page text
                    if any(k in page_text for k in ("next game", "starting in", "round starts", "next round", "countdown", "seconds")):
                        # Extract countdown value from page text
                        countdown_match = self.driver.execute_script("""
                            var els = document.querySelectorAll('*');
                            for(var i = 0; i < Math.min(els.length, 200); i++) {
                                var el = els[i];
                                var t = (el.textContent || '').trim();
                                // Look for countdown patterns
                                var m1 = t.match(/(\\d+)\\s*s/);
                                var m2 = t.match(/^(\\d{1,2})$/);
                                if(m1 && parseInt(m1[1]) <= 30) return parseInt(m1[1]);
                                if(m2 && parseInt(m2[1]) <= 30) return parseInt(m2[1]);
                            }
                            return null;
                        """)
                        if countdown_match is not None:
                            countdown_value = countdown_match
                            found_countdown = True
                except Exception:
                    pass
                
                # AGGRESSIVE countdown detection - scan ALL text on page
                if not found_countdown:
                    try:
                        aggressive_countdown = self.driver.execute_script("""
                            // Scan ALL text on page for any countdown-like numbers
                            var allText = document.body.innerText || '';
                            var lines = allText.split('\\n');
                            for(var i = 0; i < lines.length; i++) {
                                var line = lines[i].trim();
                                // Look for any number 1-30 that might be a countdown
                                var m1 = line.match(/(\\d{1,4})\\s*s/);
                                var m2 = line.match(/^(\\d{1,4})$/);
                                if(m1) {
                                    var num = parseInt(m1[1]);
                                    if(num >= 1 && num <= 30) return num;
                                }
                                if(m2) {
                                    var num = parseInt(m2[1]);
                                    if(num >= 1 && num <= 30) return num;
                                }
                            }
                            return null;
                        """)
                        if aggressive_countdown is not None:
                            countdown_value = aggressive_countdown
                            found_countdown = True
                            print(f"🔍 Found countdown via aggressive scan: {aggressive_countdown}s")
                    except Exception:
                        pass

                # More lenient countdown detection - but ONLY if round is NOT active
                # Also check for any countdown-like text on the page
                if (countdown_value is not None or found_countdown) and not is_active:
                    try:
                        countdown_int = int(countdown_value)
                    except Exception:
                        countdown_int = None
                        
                    if countdown_int is not None and 0 <= countdown_int <= 30:
                        found_countdown = True
                        if last_logged_countdown is None or countdown_int != last_logged_countdown:
                            print(f"⏳ Round starts in ~{countdown_int}s")
                            last_logged_countdown = countdown_int
                            
                        # Prepare early around 18-20s
                        if countdown_int >= 18:
                            if not self.round_prepped:
                                try:
                                    self.set_progressive_slider_exact(90)
                                    print(f"✅ Pre-set bet amount to {self.current_bet}")
                                except Exception:
                                    pass
                                self.round_prepped = True
                            print("✅ Proceeding to place bet...")
                            return True
                        # For any countdown 1-17s, stay ready to place bet immediately
                        elif 1 <= countdown_int <= 17:
                            print("✅ Proceeding to place bet...")
                            return True
                            
                # Fallback: page text heuristics - always check this
                if not found_countdown:
                    page_text = self.driver.page_source.lower()
                    if any(k in page_text for k in ("next game", "starting in", "round starts", "next round", "countdown")):
                        try:
                            countdown_value = self.driver.execute_script(
                            """
                            var els=document.querySelectorAll('*');
                            for(var el of els){
                              var t=(el.textContent||'').trim().toLowerCase();
                              var m=t.match(/(\\d+(?:\\.\\d+)?)\\s*s/);
                              if(m){ var v=parseFloat(m[1]); if(v<=30) return Math.round(v); }
                              if(/^\\d{1,2}$/.test(t)) { var n=parseInt(t,10); if(n<=30) return n; }
                            }
                            return null;
                            """
                            )
                        except Exception:
                            countdown_value = None
                            
                        if countdown_value is not None:
                            ci = int(countdown_value)
                            if last_logged_countdown is None or abs(ci - last_logged_countdown) >= 1:
                                print(f"⏳ Round starts in ~{ci}s")
                                last_logged_countdown = ci
                                
                            if int(countdown_value) >= 18:
                                if not self.round_prepped:
                                    try:
                                        self.set_progressive_slider_exact(90)
                                        print(f"✅ Pre-set bet amount to {self.current_bet}")
                                    except Exception:
                                        pass
                                    self.round_prepped = True
                                print("✅ Proceeding to place bet...")
                                return True
                            elif 1 <= int(countdown_value) <= 17:
                                print("✅ Proceeding to place bet...")
                                return True
                            
            except Exception:
                pass
            time.sleep(0.2)  # Check more frequently for better responsiveness
            
            # CRITICAL: Check if round is currently active - DON'T bet during active rounds!
            try:
                # Check for active multipliers in the page
                active_multipliers = self.driver.execute_script("""
                    var allText = document.body.innerText || '';
                    var multiplierMatch = allText.match(/\\d+\\.\\d{1,2}x/g);
                    if(multiplierMatch) {
                        var highest = 0;
                        for(var i = 0; i < multiplierMatch.length; i++) {
                            var val = parseFloat(multiplierMatch[i]);
                            if(val > highest && val >= 1.0) highest = val;
                        }
                        return highest;
                    }
                    return 0;
                """)
                
                if active_multipliers and active_multipliers > 1.0:
                    print(f"⚠️ ROUND IS ACTIVE! Multiplier: {active_multipliers:.2f}x - WAITING for round to end...")
                    time.sleep(1)
                    continue  # Don't try to bet during active rounds!
                    
            except Exception:
                pass
            
            # Force continuation if no countdown detected for 10 seconds
            if time.time() - start_time > 10 and not found_countdown:
                print("⚠️ No countdown detected for 10s - forcing continuation anyway")
                return True
            
            # ADDITIONAL: Force continuation if betting interface is visible AND no active round
            try:
                page_text = self.driver.page_source.lower()
                if any(k in page_text for k in ("place bet", "bet amount", "progressive", "cashout")):
                    # Double-check no active multipliers
                    has_multipliers = self.driver.execute_script("""
                        var allText = document.body.innerText || '';
                        return /\\d+\\.\\d{1,2}x/.test(allText);
                    """)
                    if not has_multipliers:
                        print("🔍 Found betting interface and no active multipliers - proceeding to place bet")
                        return True
            except Exception:
                pass
            
            # Also force continuation if we see betting-related text AND round is not active
            try:
                page_text = self.driver.page_source.lower()
                if any(k in page_text for k in ("place bet", "bet amount", "progressive", "cashout")):
                    # Check if round is active by looking for multipliers
                    has_multipliers = self.driver.execute_script("""
                        var allText = document.body.innerText || '';
                        return /\\d+\\.\\d{1,2}x/.test(allText);
                    """)
                    if not has_multipliers:
                        print("🔍 Found betting interface and no active multipliers - proceeding to place bet")
                        return True
            except Exception:
                pass
            
            # Debug: Show what we're seeing every 5 seconds
            if int(time.time() - start_time) % 5 == 0 and int(time.time() - start_time) > 0:
                try:
                    page_snippet = self.driver.execute_script("return document.body.innerText.substring(0, 200);")
                    print(f"🔍 Debug - Page text snippet: {page_snippet[:100]}...")
                    
                    # Also check for countdown in debug mode
                    debug_countdown = self.driver.execute_script("""
                        // Quick countdown check in debug mode
                        var allText = document.body.innerText || '';
                        var lines = allText.split('\\n');
                        for(var i = 0; i < Math.min(lines.length, 50); i++) {
                            var line = lines[i].trim();
                            var m1 = line.match(/(\\d{1,4})\\s*s/);
                            var m2 = line.match(/^(\\d{1,4})$/);
                            if(m1) {
                                var num = parseInt(m1[1]);
                                if(num >= 1 && num <= 30) return num;
                            }
                            if(m2) {
                                var num = parseInt(m2[1]);
                                if(num >= 1 && num <= 30) return num;
                            }
                        }
                        return null;
                    """)
                    if debug_countdown is not None:
                        print(f"🔍 DEBUG FOUND COUNTDOWN: {debug_countdown}s")
                except Exception:
                    pass

    def find_progressive_slider(self):
        """Locate the Progressive Cashout slider reliably by scoping to its header text."""
        try:
            ci = "translate(normalize-space(.), 'abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ')"
            # Find the header/container that mentions Progressive Cashout
            header = self.driver.find_element(
                By.XPATH,
                f"//*[contains({ci}, 'PROGRESSIVE CASHOUT') or contains({ci}, 'PROGRESSIVE')]/ancestor-or-self::*[1]"
            )
            # Look within the same section for a range input
            try:
                slider = header.find_element(By.XPATH, ".//input[@type='range']")
                return slider
            except Exception:
                pass
            # Fallback: nearest following range input
            slider = header.find_element(By.XPATH, "following::input[@type='range'][1]")
            return slider
        except Exception:
            # Final fallback: prefer the progress-slider class
            try:
                return self.driver.find_elements(By.CSS_SELECTOR, "input.progress-slider[type='range']")[-1]
            except Exception:
                sliders = self.driver.find_elements(By.XPATH, "//input[@type='range']")
                return sliders[-1] if sliders else None

    def set_progressive_slider_exact(self, target_percentage: int) -> bool:
        """Set the progressive slider to exact percentage with verification via visible label."""
        try:
            time.sleep(0.5)
            
            slider = self.find_progressive_slider()
            if not slider:
                print("⚠️ No slider found!")
                return False
            
            try:
                self.driver.execute_script("arguments[0].scrollIntoView({block: 'center', inline: 'center'});", slider)
                time.sleep(0.2)
            except Exception:
                pass

            def read_visible_percent_label() -> int:
                try:
                    return self.driver.execute_script(
                        """
                        const slider = arguments[0];
                        function isVisible(el){
                          const r = el.getBoundingClientRect();
                          const style = getComputedStyle(el);
                          return r.width>0 && r.height>0 && style.visibility!=='hidden' && style.display!=='none';
                        }
                        let scope = slider; let levels = 0; let candidates = [];
                        while(scope && levels<4){
                          candidates.push(...scope.querySelectorAll('*'));
                          scope = scope.parentElement; levels++;
                        }
                        try { candidates.push(...slider.parentElement.querySelectorAll('*')); } catch(e){}
                        let best = null; let bestDist = 1e9;
                        const sr = slider.getBoundingClientRect();
                        for(const el of candidates){
                          if(!isVisible(el)) continue;
                          const txt = (el.textContent||'').trim();
                          if(!/%/.test(txt)) continue;
                          const m = txt.match(/(\\d{1,3})%/);
                          if(!m) continue;
                          const pr = el.getBoundingClientRect();
                          const cx = pr.left + pr.width/2; const cy = pr.top + pr.height/2;
                          const dx = Math.max(0, Math.max(sr.left - cx, cx - (sr.right)));
                          const dy = Math.max(0, Math.max(sr.top - cy, cy - (sr.bottom)));
                          const dist = Math.hypot(dx, dy);
                          if(dist < bestDist){ bestDist = dist; best = {el, val: parseInt(m[1],10)}; }
                        }
                        return best ? best.val : -1;
                        """,
                        slider
                    )
                except Exception:
                    return -1

            # Quick check: if already at target, skip adjustments
            current_label = read_visible_percent_label()
            if current_label != -1 and abs(current_label - target_percentage) <= 1:
                if self.progressive_set_to != current_label:
                    self.progressive_set_to = current_label
                print(f"✅ Progressive already at ~{current_label}% (skipping)")
                return True

            print(f"🎯 Setting Progressive Cashout to {target_percentage}%...")

            try:
                slider.click()
                time.sleep(0.1)
            except Exception:
                pass

            # Method 1: Click preset button
            if self.click_preset_percentage_button(target_percentage):
                time.sleep(0.3)
                label = read_visible_percent_label()
                if label != -1 and abs(label - target_percentage) <= 1:
                    print(f"✅ Slider verified at ~{label}% via preset button")
                    self.progressive_set_to = label
                    return True

            # Method 2: JavaScript (PRIORITY for low-latency exact set)
            try:
                self.driver.execute_script(
                    """
                    var slider = arguments[0];
                    var value = arguments[1];
                    function fire(el){
                      el.dispatchEvent(new Event('input', {bubbles:true}));
                      el.dispatchEvent(new Event('change', {bubbles:true}));
                      el.dispatchEvent(new MouseEvent('mouseup', {bubbles:true}));
                    }
                    try { slider.value = value; fire(slider); } catch(e){}
                    try {
                      var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
                      setter.call(slider, value); fire(slider);
                    } catch(e){}
                    """,
                    slider, target_percentage
                )
                time.sleep(0.3)
                label = read_visible_percent_label()
                if label != -1 and abs(label - target_percentage) <= 1:
                    print(f"✅ Slider verified at ~{label}% via JS")
                    self.progressive_set_to = label
                    return True
            except Exception as e:
                print(f"JS method error: {e}")
            
            # Method 3: Keyboard (fallback only)
            try:
                slider.send_keys(Keys.END)
                time.sleep(0.2)
                
                label = read_visible_percent_label()
                if label == -1:
                    try:
                        label = int(slider.get_attribute("value"))
                    except:
                        label = 100
                
                steps_needed = label - target_percentage
                
                if steps_needed > 0:
                    for _ in range(steps_needed):
                        slider.send_keys(Keys.ARROW_LEFT)
                        time.sleep(0.03)
                    
                    time.sleep(0.25)
                    label = read_visible_percent_label()
                    if label != -1 and abs(label - target_percentage) <= 1:
                        print(f"✅ Slider verified at ~{label}% via keyboard")
                        self.progressive_set_to = label
                        return True
            except Exception as e:
                print(f"Keyboard method error: {e}")
                
            print(f"❌ ALL METHODS FAILED: Could not set slider to {target_percentage}%")
            return False
                
        except Exception as e:
            print(f"Fatal slider error: {e}")
            return False

    def is_advanced_betting_enabled(self) -> bool:
        """Check if Advanced Betting is enabled"""
        try:
            ci = "translate(normalize-space(.), 'abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ')"
            header = self.driver.find_element(
                By.XPATH,
                f"//*[contains({ci}, 'ADVANCED BETTING')]/ancestor-or-self::*[1]"
            )
            try:
                container = header.find_element(By.XPATH, ".//ancestor::*[contains(@class,'panel') or contains(@class,'flex')][1]")
            except Exception:
                container = header
            sliders = container.find_elements(By.XPATH, ".//label[contains(translate(normalize-space(.),'abcdefghijklmnopqrstuvwxyz','ABCDEFGHIJKLMNOPQRSTUVWXYZ'),'PROGRESSIVE')]/following::input[@type='range'][1] | .//input[contains(@class,'progress-slider') and @type='range']")
            for s in sliders:
                try:
                    if s.is_displayed() and s.size.get('width', 0) >= 80:
                        self.advanced_betting_on = True
                        return True
                except Exception:
                    continue
            self.advanced_betting_on = False
            return False
        except Exception:
            return False

    def place_bet_with_progressive(self, amount, progressive_percentage=90):
        """Place bet with progressive cashout"""
        print(f"💰 Placing bet: {amount} SOL with {progressive_percentage}% progressive cashout")
        
        try:
            # Set bet amount
            print("📝 Setting bet amount...")
            bet_inputs = self.driver.find_elements(By.XPATH, "//input[@type='number']")
            
            if not bet_inputs:
                bet_inputs = self.driver.find_elements(By.XPATH, "//input[contains(@value, '0.0') or contains(@placeholder, 'Bet')]")
            
            if bet_inputs:
                bet_input = bet_inputs[0]
                try:
                    bet_input.click()
                    bet_input.clear()
                    bet_input.send_keys(str(amount))
                except Exception:
                    self.driver.execute_script(
                        """
                        var el = arguments[0], v = arguments[1];
                        try { el.value=''; } catch(e) {}
                        try { el.focus(); } catch(e) {}
                        try { el.value = v; } catch(e) {}
                        try { el.dispatchEvent(new Event('input', {bubbles:true})); } catch(e) {}
                        try { el.dispatchEvent(new Event('change', {bubbles:true})); } catch(e) {}
                        """,
                        bet_input,
                        str(amount),
                    )
                time.sleep(0.3)
                print(f"✅ Bet amount set to {amount}")
            else:
                print("❌ Could not find bet input!")
                return False
            
            # Check advanced betting
            for _ in range(2):
                if self.is_advanced_betting_enabled():
                    break
                time.sleep(0.1)
            
            self.set_progressive_slider_exact(progressive_percentage)
            
            # Find and click Place Bet button
            print("🎲 Clicking Place Bet...")
            
            def find_place_bet_button():
                try:
                    buttons = self.driver.find_elements(By.XPATH, "//button[contains(translate(normalize-space(text()), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'place') and contains(translate(normalize-space(text()), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'bet')]")
                    for btn in buttons:
                        if btn.is_displayed() and btn.is_enabled():
                            return btn
                except Exception:
                    pass
                return None

            place_bet_btn = None
            for _ in range(15):
                place_bet_btn = find_place_bet_button()
                if place_bet_btn:
                    try:
                        if place_bet_btn.is_enabled():
                            break
                    except Exception:
                        pass
                time.sleep(0.1)
            
            if place_bet_btn:
                try:
                    self.driver.execute_script("arguments[0].scrollIntoView({block:'center'});", place_bet_btn)
                except Exception:
                    pass
                    
                clicked = False
                try:
                    # FORCE INSTANT JS CLICK - NO HOLDING AT ALL
                    self.driver.execute_script("""
                        var btn = arguments[0];
                        // Fire instant click event
                        var event = new MouseEvent('click', {
                            bubbles: true,
                            cancelable: true,
                            view: window
                        });
                        btn.dispatchEvent(event);
                        // Also trigger any other events
                        btn.click();
                    """, place_bet_btn)
                    clicked = True
                    print("✅ Used INSTANT JS click on Place Bet")
                except Exception as e:
                    print(f"❌ JS click failed: {e}")
                    clicked = False
                        
                if clicked:
                    print("✅ Bet placed!")
                else:
                    print("❌ Click attempts failed on Place Bet")
                
                # Handle wallet confirmation
                time.sleep(1.8)
                self.confirm_wallet_transaction()
                
                # Verify bet was placed
                time.sleep(2)
                if self.verify_bet_listed(self.player_account_name, timeout_seconds=5):
                    print(f"✅ Bet verified - {self.player_account_name} is in the Playing list")
                    return True
                else:
                    print("⚠️ Could not verify bet in Playing list")
                    return False
            else:
                print("❌ Could not find Place Bet button!")
                return False
                
        except Exception as e:
            print(f"❌ Error placing bet: {e}")
            return False
    
    def confirm_wallet_transaction(self):
        """Confirm the wallet transaction"""
        try:
            print("🔍 Looking for wallet popup...")
            
            max_wait_s = 12
            waited = 0.0
            while waited < max_wait_s:
                windows = self.driver.window_handles
                if len(windows) > 1:
                    print(f"✅ Found {len(windows)} windows, switching to wallet popup...")
                    self.driver.switch_to.window(windows[-1])
                    time.sleep(1)
                    
                    print("🔍 Looking for confirm/approve button...")
                    try:
                        for attempt in range(20):
                            buttons = self.driver.find_elements(By.TAG_NAME, "button")
                            found = None
                            for btn in buttons:
                                try:
                                    btn_text = btn.text.strip().lower()
                                    if btn_text in ["approve", "confirm", "sign"]:
                                        if btn.is_displayed() and btn.is_enabled():
                                            found = btn
                                            print(f"  Found button: '{btn_text}'")
                                            break
                                except:
                                    continue
                            
                            if found:
                                try:
                                    self.driver.execute_script("arguments[0].click();", found)
                                    print("✅ Wallet transaction confirmed!")
                                    time.sleep(0.5)
                                    break
                                except:
                                    try:
                                        found.click()
                                        print("✅ Wallet transaction confirmed!")
                                        time.sleep(0.5)
                                        break
                                    except:
                                        pass
                            time.sleep(0.5)
                    except Exception as e:
                        print(f"⚠️ Wallet popup interaction error: {e}")
                    
                    try:
                        self.driver.switch_to.window(windows[0])
                        print("✅ Switched back to main window")
                    except:
                        pass
                    return
                time.sleep(0.25)
                waited += 0.25
            print("⚠️ No wallet popup found after waiting")
                    
        except Exception as e:
            print(f"Wallet confirm error: {e}")
            try:
                self.driver.switch_to.window(self.driver.window_handles[0])
            except:
                pass
    
    def verify_bet_listed(self, player_name, timeout_seconds=5):
        """Verify that the player's bet is listed"""
        try:
            start_time = time.time()
            while time.time() - start_time < timeout_seconds:
                page_text = self.driver.page_source
                if player_name in page_text:
                    print(f"✅ Found {player_name} in page content")
                    return True
                time.sleep(0.5)
            return False
        except Exception:
            return False
    
    def monitor_progressive_cashouts(self):
        """Monitor the round with CREATIVE crash detection"""
        print("👀 Monitoring for progressive cashouts...")
        
        cashed_out_levels = []
        max_mult = 0.0
        last_mult = 0.0
        second_phase_armed = False
        
        # Creative crash detection variables
        multiplier_history = []  # Track last 20 multipliers
        stable_multiplier_count = 0  # Count how long multiplier stays same
        crash_indicators = 0  # Multiple crash signals
        round_active = False
        last_update_time = time.time()
        round_start_time = time.time()  # Track total round time
        round_ended = False  # Flag to exit monitoring loop
        
        # Setup multiplier tracker
        print("🔧 Setting up rAF multiplier tracker...")
        self.setup_multiplier_tracker()
        print("✅ rAF multiplier tracker setup complete")
        
        # Reset all tracking variables at start
        max_mult = 0.0
        last_mult = 0.0
        round_active = False
        last_update_time = time.time()
        round_start_time = time.time()
        
        # Clear any residual countdown tracking
        if hasattr(self, '_last_countdown'):
            delattr(self, '_last_countdown')
            
        # CRITICAL: Wait for page to settle before starting monitoring
        print("⏳ Waiting for page to settle before monitoring...")
        time.sleep(2)  # Give time for old multipliers to clear
        
        print("👀 Starting CREATIVE crash detection...")
        
        while not round_ended:
            try:
                current_time = time.time()
                current_mult = 0.0
                
                # Check if we should exit monitoring (safety timeout)
                if current_time - round_start_time > 300:  # 5 minute safety timeout
                    print("⚠️ Safety timeout reached - forcing round end")
                    round_ended = True
                    break
                
                # CREATIVE METHOD 1: Multiple detection approaches
                multiplier_sources = []
                
                # CRITICAL: Don't read multipliers during countdown phase
                countdown_check = None
                try:
                    countdown_check = self.driver.execute_script("return window.roundCountdownSeconds || null;")
                except Exception:
                    pass
                
                # If countdown is active, skip all multiplier reading
                if countdown_check is not None:
                    current_mult = 0.0
                    # Don't log anything during countdown - completely skip multiplier processing
                    pass
                else:
                
                    # Use multiple multiplier sources for better detection
                    try:
                        mult1 = self._read_center_multiplier()
                        if mult1 and mult1 > 0:
                            multiplier_sources.append(mult1)
                    except Exception:
                        pass
                    
                    # Source 2: Window tracker - more lenient timing
                    try:
                        mult2_result = self.driver.execute_script("""
                            // Don't read during countdown
                            if(window.roundCountdownSeconds !== null && window.roundCountdownSeconds !== undefined) {
                                return 0;
                            }
                            
                            var mult = window.currentMultiplier || 0;
                            var lastChange = window._lastMultChange || 0;
                            var now = performance.now();
                            
                            // More lenient timing - 3 seconds instead of 1
                            if(mult > 0 && (now - lastChange) < 3000) {
                                return mult;
                            }
                            return 0;
                        """)
                        if mult2_result and mult2_result > 0:
                            multiplier_sources.append(mult2_result)
                    except Exception:
                        pass
                    
                    # Source 3: Fallback DOM scan with wider criteria
                    try:
                        mult3_result = self.driver.execute_script("""
                            if(window.roundCountdownSeconds !== null && window.roundCountdownSeconds !== undefined) {
                                return 0;
                            }
                            
                            var all = document.querySelectorAll('*');
                            var best = 0;
                            for(var i = 0; i < Math.min(all.length, 100); i++) {
                                var el = all[i];
                                var t = (el.textContent || '').trim();
                                var m = t.match(/(\\d+\\.\\d{1,2})x/i);
                                if(m) {
                                    var v = parseFloat(m[1]);
                                    if(v >= 1.00 && v <= 1000) {
                                        var rect = el.getBoundingClientRect();
                                        // Must be in center area and visible
                                        if(rect.top > window.innerHeight * 0.2 && rect.width > 0) {
                                            best = Math.max(best, v);
                                        }
                                    }
                                }
                            }
                            return best;
                        """)
                        if mult3_result and mult3_result > 0:
                            multiplier_sources.append(mult3_result)
                    except Exception:
                        pass
                
                # NOTE: Deliberately removed DOM-wide scan to avoid picking up stale/animated values
                
                    # Use the highest multiplier found
                    if multiplier_sources:
                        candidate = max(multiplier_sources)
                        # Anti-spike filter: ignore improbable jumps (e.g., 2.0 -> 500x)
                        if last_mult > 0:
                            if candidate > max(last_mult + 1.0, last_mult * 1.8) and candidate > 3.0:
                                # Treat as noise; do not update this tick
                                candidate = 0.0
                        current_mult = candidate
                
                # CREATIVE METHOD 2: Detect crashes through multiple signals
                if current_mult > 0:
                    # Round is active ONLY if we see meaningful multipliers AND no countdown
                    countdown_check = None
                    try:
                        countdown_check = self.driver.execute_script("return window.roundCountdownSeconds || null;")
                    except Exception:
                        pass
                    
                        # Only consider round active if we have FRESH multipliers AND no countdown
                    # Also require multiplier to be reasonable (1.00-1.10x range for new rounds)
                    if current_mult >= 1.01 and countdown_check is None:
                        # For new rounds, multiplier should start low (1.00-1.20x)
                        # If we see high multipliers (>5x) immediately, it's probably stale data
                        if not round_active:
                            if current_mult > 5.0:
                                print(f"⚠️ Ignoring stale high multiplier: {current_mult:.2f}x - waiting for fresh round")
                                current_mult = 0  # Ignore this reading
                            else:
                                round_start_time = current_time  # Reset when round actually starts
                                print(f"🚀 Round started! First multiplier: {current_mult:.2f}x")
                                # Clear any previous crash indicators when round truly starts
                                crash_indicators = 0
                                max_mult = 0.0  # Reset max multiplier
                                multiplier_history = []
                                stable_multiplier_count = 0
                                round_active = True
                        else:
                            round_active = True
                        last_update_time = current_time
                    elif countdown_check is not None:
                        # We have countdown - this means betting phase, not game phase
                        if round_active:
                            print("🔄 Countdown detected during round - switching to betting phase")
                        round_active = False
                    
                    # Log multiplier changes
                    if abs(current_mult - last_mult) > 0.005:
                        print(f"📈 {current_mult:.2f}x")
                        
                        # INSTANT CRASH DETECTION: Check for backwards movement
                        if round_active and max_mult > 1.05 and current_mult < last_mult and last_mult > 0:
                            final_mult = max_mult
                            print(f"💥 INSTANT CRASH: Multiplier went backwards from {last_mult:.2f}x to {current_mult:.2f}x")
                            print("⏱️ Round ended - starting next betting cycle...")
                            if hasattr(self, '_last_countdown'):
                                delattr(self, '_last_countdown')
                            round_ended = True
                            break
                        
                        last_mult = current_mult
                        stable_multiplier_count = 0
                    else:
                        stable_multiplier_count += 1
                    
                    # Track multiplier history
                    multiplier_history.append(current_mult)
                    if len(multiplier_history) > 20:
                        multiplier_history.pop(0)
                    
                    # Update max
                    if current_mult > max_mult:
                        max_mult = current_mult
                    
                    # Reset crash indicators
                    crash_indicators = 0
                    
                    # Cashout logic - SIMPLIFIED
                    if round_active and current_mult > 0:
                        # First target 1.25x
                        if current_mult >= 1.25 and 1.25 not in cashed_out_levels:
                            if self.click_cashout():
                                print(f"💰 Progressive cashout at {current_mult:.2f}x!")
                                cashed_out_levels.append(1.25)
                                print("🔄 Switching Progressive to 50% for second cashout...")
                                try:
                                    if self.set_progressive_slider_exact(50):
                                        print("✅ Switched Progressive to 50% using same method as 90%")
                                    else:
                                        print("⚠️ Failed to set slider to 50% using the same method")
                                except Exception as e:
                                    print(f"⚠️ Error setting slider to 50%: {e}")
                                second_phase_armed = True
                                # Reset crash detection after first cashout
                                crash_indicators = 0
                                last_update_time = current_time  # Reset timer for second phase
                                second_phase_start_time = current_time  # Track second phase start
                        # Second target 5x
                        elif second_phase_armed and (5.0 not in cashed_out_levels) and current_mult >= 5.00:
                            if self.click_cashout():
                                print(f"💰 Second cashout at {current_mult:.2f}x!")
                                cashed_out_levels.append(5.0)
                                # CRITICAL: Exit monitoring after second cashout
                                print("🎯 Both progressive cashouts completed - exiting monitoring")
                                round_ended = True
                                break
                
                else:
                    # No multiplier detected - progressive backoff and robust next-round wait
                    if round_active:
                        crash_indicators += 1
                        
                        # IMMEDIATE CRASH DETECTION: If no multiplier for too long, force crash
                        # Less aggressive during second phase
                        timeout_seconds = 5.0 if second_phase_armed else 2.0
                        if (current_time - last_update_time) > timeout_seconds:
                            final_mult = max_mult if max_mult > 0 else 1.0
                            print(f"💥 IMMEDIATE CRASH: No multiplier for {timeout_seconds}s, final: {final_mult:.2f}x")
                            print("⏱️ Round ended - starting next betting cycle...")
                            if hasattr(self, '_last_countdown'):
                                delattr(self, '_last_countdown')
                            round_ended = True
                            break
                        
                        # Do not spam logs
                        
                        # SIGNAL 1: Time since last multiplier update (AGGRESSIVE)
                        time_since_update = current_time - last_update_time
                        if time_since_update > 1.0:  # Just 1 second without multiplier
                            crash_indicators += 3
                            print(f"⏰ {time_since_update:.1f}s since last multiplier")
                        
                        # SIGNAL 2: Check for crash-related text on page
                        try:
                            page_text = self.driver.page_source.lower()
                            if any(word in page_text for word in ['crashed', 'bust', 'busted', 'lost']):
                                crash_indicators += 5
                                print("💥 Found crash text on page!")
                        except Exception:
                            pass
                        
                        # SIGNAL 3: Check if countdown appeared (new round starting) - ONLY if we had multipliers AND sufficient time passed
                        if max_mult > 1.05 and (current_time - round_start_time) > 5.0:  # Must have real multipliers AND 5+ seconds of gameplay
                            try:
                                countdown_check = self.driver.execute_script("""
                                    var els = document.querySelectorAll('*');
                                    for(var i=0; i<Math.min(els.length, 100); i++){
                                        var t = (els[i].textContent || '').trim();
                                        if(/^\\d{1,2}$/.test(t) || /\\d+\\s*s/.test(t.toLowerCase())) return true;
                                    }
                                    return false;
                                """)
                                if countdown_check:
                                    crash_indicators += 5
                                    print("🔄 Countdown detected after multipliers - round crashed!")
                            except Exception:
                                pass
                        
                        # SIGNAL 4: Stable multiplier for too long (AGGRESSIVE)
                        if stable_multiplier_count > 20:  # Just 1 second of same multiplier
                            crash_indicators += 2
                            print(f"⏸️ Multiplier stable for {stable_multiplier_count} ticks")
                        
                        # DECLARE CRASH when sufficient signals - BUT ONLY if we had a real round
                        if crash_indicators >= 2 and max_mult > 1.05 and (current_time - round_start_time) > 3.0:
                            # Use the LATEST multiplier reading, not the stored max_mult
                            final_mult = current_mult if current_mult > 0 else max_mult
                            print(f"💥 CRASH DETECTED! Signals: {crash_indicators}, Final: {final_mult:.2f}x")
                            print(f"💥 Crashed at {final_mult:.2f}x")
                            print("⏱️ Round ended - starting next betting cycle in 3 seconds...")
                            # Reset countdown tracking for next round
                            if hasattr(self, '_last_countdown'):
                                delattr(self, '_last_countdown')
                            time.sleep(3)
                            # Set flag to exit monitoring loop
                            round_ended = True
                            break
                        
                        # CRASH DETECTION: Check for multiplier drops (clear crash signal)
                        if round_active and max_mult > 1.05 and current_mult < max_mult * 0.8:
                            final_mult = max_mult
                            print(f"💥 CRASH DETECTED: Multiplier dropped from {max_mult:.2f}x to {current_mult:.2f}x")
                            print("⏱️ Round ended - starting next betting cycle...")
                            if hasattr(self, '_last_countdown'):
                                delattr(self, '_last_countdown')
                            round_ended = True
                            break
                        
                        # INSTANT CRASH DETECTION: If multiplier goes backwards, it's crashed
                        if round_active and max_mult > 1.05 and current_mult < last_mult and last_mult > 0:
                            final_mult = max_mult
                            print(f"💥 INSTANT CRASH: Multiplier went backwards from {last_mult:.2f}x to {current_mult:.2f}x")
                            print("⏱️ Round ended - starting next betting cycle...")
                            if hasattr(self, '_last_countdown'):
                                delattr(self, '_last_countdown')
                            round_ended = True
                            break
                        
                        # AGGRESSIVE CRASH DETECTION: If no multiplier for too long, force crash
                        # Less aggressive during second phase to avoid false positives
                        timeout_seconds = 8.0 if second_phase_armed else 4.0
                        if round_active and max_mult > 1.05 and (current_time - last_update_time) > timeout_seconds:
                            final_mult = max_mult
                            print(f"💥 AGGRESSIVE CRASH DETECTION: No multiplier for {timeout_seconds}s, final: {final_mult:.2f}x")
                            print("⏱️ Round ended - starting next betting cycle...")
                            if hasattr(self, '_last_countdown'):
                                delattr(self, '_last_countdown')
                            time.sleep(2)
                            # Set flag to exit monitoring loop
                            round_ended = True
                            break
                        
                        # ADDITIONAL: Force round end if no multiplier for too long AND we had a real round
                        if round_active and max_mult > 1.05 and (current_time - last_update_time) > 3.0:
                            final_mult = max_mult
                            print(f"⏰ FORCE ROUND END: No multiplier for 3s, final: {final_mult:.2f}x")
                            print("⏱️ Round ended - starting next betting cycle...")
                            if hasattr(self, '_last_countdown'):
                                delattr(self, '_last_countdown')
                            time.sleep(2)
                            # Set flag to exit monitoring loop
                            round_ended = True
                            break
                
                # FAILSAFE: Force crash detection after 120 seconds of monitoring (2 minutes)
                total_round_time = current_time - round_start_time
                if round_active and total_round_time > 120:
                    final_mult = current_mult if current_mult > 0 else max_mult
                    print(f"⏰ FAILSAFE: Round running for {total_round_time:.1f}s - forcing crash detection")
                    print(f"💥 FORCED CRASH! Crashed at {final_mult:.2f}x")
                    time.sleep(2)  # Shorter wait
                    # Set flag to exit monitoring loop
                    round_ended = True
                    break
                
                # ULTIMATE FAILSAFE: Force return after 180 seconds total (3 minutes)
                if total_round_time > 180:
                    final_mult = max_mult if max_mult > 0 else 1.0
                    print(f"🚨 ULTIMATE FAILSAFE: Round stuck for {total_round_time:.1f}s - forcing return")
                    print(f"💥 FORCED RETURN! Final: {final_mult:.2f}x")
                    time.sleep(1)
                    # Set flag to exit monitoring loop
                    round_ended = True
                    break
                
                # CRITICAL FAILSAFE: Force exit if monitoring takes too long (prevents infinite freezing)
                if total_round_time > 30:
                    final_mult = max_mult if max_mult > 0 else 1.0
                    print(f"🚨 CRITICAL FAILSAFE: Monitoring stuck for {total_round_time:.1f}s - FORCING EXIT")
                    print(f"💥 FORCED EXIT! Final: {final_mult:.2f}x")
                    round_ended = True
                    break
                
                # SECOND PHASE FAILSAFE: Exit if second phase takes too long (but only if no recent multiplier updates)
                if second_phase_armed and (current_time - second_phase_start_time) > 30.0 and (current_time - last_update_time) > 5.0:
                    final_mult = max_mult
                    print(f"⏰ SECOND PHASE TIMEOUT: Second phase took >30s with no updates, final: {final_mult:.2f}x")
                    print("⏱️ Round ended - starting next betting cycle...")
                    if hasattr(self, '_last_countdown'):
                        delattr(self, '_last_countdown')
                    round_ended = True
                    break
                
                # ADDITIONAL FAILSAFE: Exit if we've been monitoring for more than 60 seconds
                if total_round_time > 60:
                    final_mult = max_mult if max_mult > 0 else 1.0
                    print(f"⏰ MONITORING TIMEOUT: Been monitoring for {total_round_time:.1f}s - forcing exit")
                    print(f"💥 FORCED EXIT! Final: {final_mult:.2f}x")
                    time.sleep(1)
                    round_ended = True
                    break
                
                # Show countdown if detected - but DON'T crash during betting window
                try:
                    countdown = self.driver.execute_script("return window.roundCountdownSeconds || null;")
                    if countdown is not None and countdown <= 20:
                        countdown_int = int(countdown)
                        if countdown_int != getattr(self, '_last_countdown', None):
                            print(f"⏳ Round starts in ~{countdown_int}s")
                            self._last_countdown = countdown_int
                        
                        # If we see countdown, this means we're in betting phase - RESET everything
                        if countdown is not None:
                            # This is betting window - reset all round tracking
                            if round_active:
                                print("🔄 Betting window detected - resetting round tracking")
                            round_active = False
                            max_mult = 0.0
                            last_mult = 0.0
                            crash_indicators = 0
                            multiplier_history = []
                            stable_multiplier_count = 0
                            # Clear stale multiplier tracking
                            if hasattr(self, '_same_mult_count'):
                                self._same_mult_count = 0
                            # DON'T return here - this is normal betting phase
                    elif countdown is None and round_active:
                        # Reset countdown tracking when no countdown detected
                        if hasattr(self, '_last_countdown'):
                            delattr(self, '_last_countdown')
                except Exception:
                    pass
                
                time.sleep(0.1)  # Slightly slower to reduce CPU usage
                
            except Exception as e:
                print(f"⚠️ Monitor error: {e}")
                time.sleep(0.1)
        
        print(f"⏱️ Round ended. Max multiplier: {max_mult:.2f}x")
        # Reset countdown tracking for next round
        if hasattr(self, '_last_countdown'):
            delattr(self, '_last_countdown')
        
        # SAFETY: Ensure we always return something
        if max_mult <= 0:
            max_mult = 1.0  # Default value if no multiplier detected
        
        return (len(cashed_out_levels) > 0), max_mult

    def click_preset_percentage_button(self, percentage: int) -> bool:
        """Try to click a preset percentage button with multiple strategies"""
        try:
            label = f"{percentage}%"
            slider = self.find_progressive_slider()
            if not slider:
                return False
                
            # Strategy 1: Look globally for percentage buttons
            try:
                global_buttons = self.driver.find_elements(By.XPATH, f"//button[normalize-space(text())='{label}']")
                for btn in global_buttons:
                    try:
                        if btn.is_displayed() and btn.is_enabled():
                            btn.click()
                            print(f"✅ Clicked {label} button (global)")
                            return True
                    except Exception:
                        try:
                            self.driver.execute_script("arguments[0].click();", btn)
                            print(f"✅ Clicked {label} button (global JS)")
                            return True
                        except Exception:
                            continue
            except Exception:
                pass
                
            # Strategy 2: Look near slider
            container = slider
            for _ in range(4):
                try:
                    parent = container.find_element(By.XPATH, "..")
                    if parent:
                        container = parent
                except Exception:
                    break
                    
            # Look for button with exact percentage text
            buttons = container.find_elements(By.XPATH, ".//button")
            for btn in buttons:
                btn_text = btn.text.strip()
                if btn_text == label:
                    try:
                        btn.click()
                        print(f"✅ Clicked {btn_text} button (scoped)")
                        return True
                    except Exception:
                        try:
                            self.driver.execute_script("arguments[0].click();", btn)
                            print(f"✅ Clicked {btn_text} button (scoped JS)")
                            return True
                        except Exception:
                            continue
                    
            # Strategy 3: Try nested text approach
            try:
                alt = container.find_elements(By.XPATH, f".//*[normalize-space(text())='{label}']/ancestor::button[1]")
                for btn in alt:
                    try:
                        if btn.is_displayed():
                            try:
                                btn.click()
                                print(f"✅ Clicked {label} via nested text")
                                return True
                            except Exception:
                                self.driver.execute_script("arguments[0].click();", btn)
                                print(f"✅ Clicked {label} via nested text JS")
                                return True
                    except Exception:
                        continue
            except Exception:
                pass
                
            # Strategy 4: Direct JS slider setting for 50%
            if percentage == 50:
                try:
                    print("🔧 Attempting direct JS slider set to 50%...")
                    # Use comprehensive JS approach
                    result = self.driver.execute_script("""
                        var slider = arguments[0];
                        try {
                            // Multiple approaches to set slider value
                            slider.value = 50;
                            
                            // Fire all relevant events
                            var events = ['input', 'change', 'mousedown', 'mouseup', 'click'];
                            events.forEach(function(eventType) {
                                try {
                                    var event = new Event(eventType, {bubbles: true, cancelable: true});
                                    slider.dispatchEvent(event);
                                } catch(e) {}
                            });
                            
                            // Try property descriptor approach
                            try {
                                var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
                                setter.call(slider, '50');
                            } catch(e) {}
                            
                            // Fire more events
                            try {
                                slider.dispatchEvent(new MouseEvent('mouseup', {bubbles: true}));
                                slider.dispatchEvent(new Event('change', {bubbles: true}));
                            } catch(e) {}
                            
                            return slider.value;
                        } catch(e) {
                            return 'error: ' + e.message;
                        }
                    """, slider)
                    
                    time.sleep(0.5)
                    print(f"✅ JS slider set result: {result}")
                    
                    # Verify the setting worked
                    try:
                        current_value = slider.get_attribute('value')
                        if current_value and abs(int(current_value) - 50) <= 5:
                            print("✅ Slider successfully set to ~50%")
                            return True
                    except Exception:
                        pass
                        
                    print("✅ Attempted JS slider set to 50%")
                    return True
                except Exception as e:
                    print(f"JS slider set failed: {e}")
            
            print(f"⚠️ Could not find or set {percentage}% button")
            return False
        except Exception:
            return False
            
    def click_cashout(self):
        """Click the cashout button"""
        try:
            buttons = self.driver.find_elements(By.TAG_NAME, "button")
            for btn in buttons:
                btn_text = btn.text.lower()
                if ("cash" in btn_text and "out" in btn_text) or "cashout" in btn_text:
                    if btn.is_enabled() and btn.is_displayed():
                        try:
                            btn.click()
                            return True
                        except:
                            self.driver.execute_script("arguments[0].click();", btn)
                            return True
            return False
        except:
            return False
    
    def clear_multiplier_state(self):
        """Forcefully clear all multiplier tracking state"""
        try:
            self.driver.execute_script("""
                // NUCLEAR CLEAR - Force clear ALL multiplier tracking variables
                window.currentMultiplier = 0.0;
                window.lastMultiplierText = "";
                window.isGameActive = false;
                window.multiplierElement = null;
                window.centerDisplay = null;
                window.countdownElement = null;
                window.roundCountdownSeconds = null;
                window._lastMultChange = 0;
                window._dirty = true;
                
                // Clear any cached DOM references and force re-scan
                try { if (window.multiplierRafId) cancelAnimationFrame(window.multiplierRafId); } catch(e) {}
                try { if (window.multiplierTracker) clearInterval(window.multiplierTracker); } catch(e) {}
                
                // NUCLEAR: Clear ALL cached element data that might hold stale multipliers
                var allElements = document.querySelectorAll('*');
                for(var i = 0; i < Math.min(allElements.length, 200); i++) {
                    try {
                        var el = allElements[i];
                        if(el._cachedMultiplier) delete el._cachedMultiplier;
                        if(el._lastText) delete el._lastText;
                        if(el._lastMultUpdate) delete el._lastMultUpdate;
                        // Clear any cached text content
                        if(el._oldText) delete el._oldText;
                    } catch(e) {}
                }
                
                // Force page refresh of dynamic content
                try {
                    var event = new Event('DOMContentLoaded');
                    document.dispatchEvent(event);
                } catch(e) {}
            """)
            print("🗑️ NUCLEAR cleared all multiplier state")
            # Also clear Python-side tracking
            if hasattr(self, '_same_mult_count'):
                self._same_mult_count = 0
        except Exception as e:
            print(f"⚠️ Error clearing multiplier state: {e}")
    
    def run_martingale_session(self):
        """Run a complete martingale betting session with progressive cashouts"""
        print("\n" + "="*50)
        print("🎯 Starting Martingale Session with Progressive Cashouts")
        print("="*50)
        
        # Initialize multiplier tracking
        print("🔍 Initializing multiplier tracking...")
        self.setup_multiplier_tracker()
        
        self.betting_active = True
        self.current_bet = self.base_bet
        round_num = 0
        
        # Must place at least two bets every session, then continue infinitely
        bets_this_session = 0
        round_num = 0  # Only increment after a round actually completes
        consecutive_failures = 0  # Track consecutive bet failures
        
        print("🔁 STARTING INFINITE BETTING LOOP")
        print("⚠️ This loop should run FOREVER - if it stops, there's a bug!")
        
        loop_count = 0
        while self.betting_active:  # Infinite loop - remove max_bet limit
            loop_count += 1
            print(f"\n🔄 === LOOP ITERATION #{loop_count} (Active: {self.betting_active}) ===")
            print(f"\n🎲 Attempting Bet: {self.current_bet:.4f} SOL (Session: {bets_this_session}/2)")
            print(f"🔍 Betting active: {self.betting_active}, Round: {round_num}")
            
            # Keep trying to place bet until successful
            bet_placed = False
            retry_count = 0
            max_retries = 25
            
            # Check browser connection before starting
            try:
                self.driver.current_url
            except Exception as e:
                print(f"⚠️ Browser connection lost: {e}")
                print("🔄 Attempting to recover browser connection...")
                try:
                    self.driver.quit()
                    time.sleep(2)
                    self.setup_driver()
                    self.navigate_to_solpump()
                    print("✅ Browser connection recovered")
                except Exception as recovery_error:
                    print(f"❌ Failed to recover browser connection: {recovery_error}")
                    continue
            
            while not bet_placed and retry_count < max_retries:
                if retry_count > 0:
                    print(f"🔄 Retry {retry_count}/{max_retries}")
                
                # Wait for betting window - no timeout
                try:
                    self.wait_for_betting_window()
                except Exception as e:
                    print(f"⚠️ Betting window error: {e}, retrying...")
                    retry_count += 1
                    time.sleep(2)
                    continue
                
                # Set progressive cashout percentage
                print(f"🎯 Setting Progressive Cashout to {self.progressive_set_to}%...")
                if not self.set_progressive_slider_exact(self.progressive_set_to):
                    print("⚠️ Could not set progressive cashout, continuing anyway...")
                
                # Pre-set bet amount
                print(f"✅ Pre-set bet amount to {self.current_bet}")
                
                # Place bet with progressive
                print("✅ Proceeding to place bet...")
                if self.place_bet_with_progressive(self.current_bet, self.progressive_set_to):
                    bet_placed = True
                    break
                else:
                    print("❌ Failed to place bet, retrying...")
                    retry_count += 1
                    time.sleep(2)  # Longer wait between retries
            
            if not bet_placed:
                consecutive_failures += 1
                print(f"❌ Max retries reached ({consecutive_failures} consecutive failures), waiting for next opportunity...")
                
                # If too many consecutive failures, reset some things
                if consecutive_failures >= 3:
                    print("⚠️ Too many consecutive failures - resetting multiplier tracking")
                    self.clear_multiplier_state()
                    self.setup_multiplier_tracker()
                    consecutive_failures = 0
                
                time.sleep(2)
                # FORCE continue to next iteration
                continue
            else:
                # Reset failure counter on successful bet
                consecutive_failures = 0
            
            # Only increment round_num and monitor if bet was actually placed
            if bet_placed:
                round_num += 1
                print(f"🎮 Round {round_num} - Monitoring...")
                
                # Reinitialize multiplier tracking before each round
                print("🔧 Reinitializing multiplier tracker for new round...")
                self.clear_multiplier_state()
                self.setup_multiplier_tracker()
                
                # DON'T clear betting window state - let it transition naturally
                
                try:
                    won, max_multiplier = self.monitor_progressive_cashouts()
                except KeyboardInterrupt:
                    print("\n👋 User interrupted round monitoring - continuing to next bet...")
                    won = False
                    max_multiplier = 0.0
                except Exception as e:
                    print(f"⚠️ Round monitoring error: {e} - continuing to next bet...")
                    won = False
                    max_multiplier = 0.0
                
                # Reset progressive slider back to 90% for next round
                print("🔄 Resetting Progressive Cashout to 90% for next round...")
                self.progressive_set_to = 90
                
                print(f"🔍 Round {round_num} completed. Won: {won}, Max: {max_multiplier:.2f}x")
                print("🔁 ROUND MONITORING COMPLETED - CONTINUING TO NEXT BET")
                
                                                            # CRITICAL: Add timeout to prevent getting stuck
                print("⏰ Adding 2-second timeout before next bet...")
                time.sleep(2)
                
                # Force continue to next bet since round completed successfully
                print("✅ Round monitoring successful - proceeding to next betting cycle")
            else:
                # If no bet was placed, skip monitoring and try again
                print("⚠️ No bet placed, skipping round monitoring")
                won = False
                max_multiplier = 0.0
                time.sleep(1)
            
            # Process results ONLY if we actually monitored a round
            if bet_placed:
                if won:
                    print(f"✅ WON! Progressive cashout successful")
                    print(f"💰 Profit: {self.current_bet * 0.125:.4f} SOL")
                    bets_this_session += 1
                    if bets_this_session < 2:
                        print("🔁 Placing mandatory second bet at same stake...")
                        print("⏭️ Continuing to next betting cycle...")
                    else:
                        # After 2 bets, reset session and continue infinitely
                        print("🎯 Session complete! Starting new session...")
                        bets_this_session = 0
                        self.current_bet = self.base_bet
                        print("⏭️ Continuing to next betting cycle...")
                else:
                    print(f"❌ LOST! Crashed at {max_multiplier:.2f}x")
                    bets_this_session += 1
                    if bets_this_session <= 1:
                        self.current_bet = min(self.current_bet * 2, self.max_bet)
                        print(f"📈 First bet lost, doubling to {self.current_bet:.4f} SOL for second bet")
                    else:
                        # Continue martingale until win, then reset
                        self.current_bet = min(self.current_bet * 2, self.max_bet)
                        print(f"📈 Continuing martingale, doubling to {self.current_bet:.4f} SOL")
                    
                    if self.current_bet > self.max_bet:
                        print("⚠️ Max bet reached! Resetting to base bet and starting new session")
                        self.current_bet = self.base_bet
                        bets_this_session = 0
                    
                    print("⏭️ Continuing to next betting cycle...")
            
            print("🔄 Preparing for next round...")
            
            # DON'T clear game state here - it interferes with countdown detection
            # Let the page naturally transition to betting phase
            print("🔧 Allowing page to naturally transition to betting phase")
            
            # After a round completes, force refresh the page state
            if max_multiplier > 0:
                print("🔄 Round completed - refreshing page state...")
                try:
                    # Force refresh the page state without clearing countdown
                    self.driver.execute_script("""
                        // Refresh page state but keep countdown detection
                        window.currentMultiplier = 0;
                        window.lastMultiplierText = "";
                        window.isGameActive = false;
                        // DON'T clear roundCountdownSeconds - let it be detected naturally
                    """)
                except Exception:
                    pass
                time.sleep(2)
            
            time.sleep(0.5)  # Shorter wait
            # FORCE continue the loop - don't let it get stuck
            print(f"🔁 CONTINUING BETTING LOOP... (Next bet: {self.current_bet:.4f} SOL)")
            print(f"🔄 LOOP ITERATION #{loop_count} COMPLETE - STARTING NEXT BET ATTEMPT")
            print(f"🔄 Loop will continue infinitely... (betting_active: {self.betting_active})")
            
            # Ensure betting_active stays True
            if not self.betting_active:
                print("⚠️ WARNING: betting_active became False! Resetting to True")
                self.betting_active = True
    
    def monitor_mode(self):
        """Monitor mode - wait for user input to start betting"""
        print("\n" + "="*50)
        print("👀 MONITORING MODE")
        print("="*50)
        print("Commands:")
        print("  '7' = Force start betting")
        print("  'R' = Restart script")
        print("  Ctrl+C = Exit")
        print("="*50)
        while True:
            try:
                user_input = input().strip()
                if user_input == '7':
                    print("\n🎯 MANUAL TRIGGER ACTIVATED!")
                    # Start infinite betting
                    try:
                        self.run_martingale_session()
                    except KeyboardInterrupt:
                        print("\n👋 User interrupted betting session")
                        return "EXIT"
                    except Exception as e:
                        print(f"\n❌ Betting session error: {e}")
                        continue
                elif user_input.upper() == 'R':
                    print("\n🔄 Restarting...")
                    return "RESTART"
                elif user_input.upper() == 'Q':
                    print("\n👋 Exiting...")
                    return "EXIT"
            except KeyboardInterrupt:
                print("\n👋 User pressed Ctrl+C - Exiting monitor mode...")
                return "EXIT"
            except EOFError:
                print("\n⚠️ Input stream closed - this might be why betting stopped")
                time.sleep(1)
                continue
            except Exception as e:
                print(f"\n⚠️ Monitor mode error: {e}")
                time.sleep(1)
                continue
    
    def setup_multiplier_tracker(self):
        """Setup the multiplier tracker using requestAnimationFrame"""
        try:
            script = """
            // Clear any existing trackers
            try { if (window.multiplierTracker) clearInterval(window.multiplierTracker); } catch(e) {}
            try { if (window.multiplierRafId) cancelAnimationFrame(window.multiplierRafId); } catch(e) {}
            
            // FORCE RESET all multiplier tracking variables
            window.currentMultiplier = 0.0;
            window.lastMultiplierText = "";
            window.isGameActive = false;
            window.multiplierElement = null;
            window.lastScanAt = 0;
            window.roundCountdownSeconds = null;
            window.countdownElement = null;
            window._dirty = true;
            window._lastMultChange = 0;
            window.centerDisplay = null;
            
            // Clear any cached elements that might show old multipliers
            window.multiplierElement = null;
            window.centerDisplay = null;
            window.countdownElement = null;

            function isValidText(txt){
                if(!txt) return false;
                return /^\\d+\\.\\d{2}x$/i.test(txt.trim());
            }

            function lightweightRead(){
                try{ if(!window.multiplierElement) return null; var t=window.multiplierElement.textContent; if(isValidText(t)){return {v:parseFloat(t.replace('x','')), t:t};}}catch(e){}
                return null;
            }

            function findKnownMultiplierElement(){
                try {
                    var selectors = [
                        "div.font-chakra.italic.text-center.inline-grid",
                        "div.font-chakra.text-center.inline-grid",
                        "div.font-chakra.italic",
                        "div.inline-grid.font-chakra",
                    ];
                    for (var i=0;i<selectors.length;i++){
                        var els = document.querySelectorAll(selectors[i]);
                        for (var j=0;j<els.length;j++){
                            var el = els[j];
                            var txt = (el.textContent||'').trim();
                            if (isValidText(txt)) return el;
                        }
                    }
                } catch(e) {}
                return null;
            }

            function scanForElement(){
                var cx=window.innerWidth/2, cy=window.innerHeight/2; var offsets=[-150,-90,-30,0,30,90,150];
                var best=null, bestScore=-1;
                for(var i=0;i<offsets.length;i++){
                    var row=(document.elementsFromPoint(cx, cy+offsets[i])||[]).slice(0,12);
                    for(var j=0;j<row.length;j++){
                        var el=row[j]; if(!el) continue;
                        var txt=(el.textContent||'').trim(); if(!isValidText(txt)) continue;
                        var r=el.getBoundingClientRect(); if(r.width<=0||r.height<=0) continue;
                        var fs=0; try{ fs=parseFloat(getComputedStyle(el).fontSize)||0; }catch(e){}
                        var score=fs*3 + r.width*r.height*0.02;
                        if(score>bestScore){ bestScore=score; best=el; }
                    }
                }
                return best;
            }

            function isCountdownText(txt){
                if(!txt) return false; txt = txt.trim().toLowerCase();
                if(/^[0-9]{1,2}$/.test(txt)) return true;
                var m = txt.match(/(\\d+(?:\\.\\d+)?)\\s*s/);
                return !!m;
            }

            function parseCountdownValue(txt){
                if(!txt) return null; txt = txt.trim().toLowerCase();
                if(/^[0-9]{1,2}$/.test(txt)) return parseInt(txt,10);
                var m = txt.match(/(\\d+(?:\\.\\d+)?)\\s*s/);
                if(m) return parseFloat(m[1]);
                var m2 = txt.match(/(starting|next)[^\\d]*(\\d+(?:\\.\\d+)?)/);
                if(m2) return parseFloat(m2[2]);
                return null;
            }

            function scanForCountdown(){
                var cx=window.innerWidth/2, cy=window.innerHeight/2;
                var offsets=[-150,-90,-30,0,30,90,150];
                for(var i=0;i<offsets.length;i++){
                    var row=(document.elementsFromPoint(cx, cy+offsets[i])||[]).slice(0,12);
                    for(var j=0;j<row.length;j++){
                        var el=row[j]; if(!el) continue;
                        var txt=(el.textContent||'').trim(); if(!isCountdownText(txt)) continue;
                        var val = parseCountdownValue(txt); if(val!=null && val>=0 && val<=60) return {el: el, val: val};
                    }
                }
                return null;
            }

            function scanForCenterDisplay(){
                var cx=window.innerWidth/2, cy=window.innerHeight/2;
                var offsets=[-120,-60,0,60,120]; var best=null, bestScore=-1;
                for(var i=0;i<offsets.length;i++){
                    var row=(document.elementsFromPoint(cx, cy+offsets[i])||[]).slice(0,24);
                    for(var j=0;j<row.length;j++){
                        var el=row[j]; if(!el) continue;
                        var txt=(el.textContent||'').trim(); if(!txt) continue;
                        var r=el.getBoundingClientRect(); if(r.width<=0||r.height<=0) continue;
                        var fs=0; try{ fs=parseFloat(getComputedStyle(el).fontSize)||0; }catch(e){}
                        if(fs<36) continue;
                        var score = fs*3 + r.width*r.height*0.02;
                        if(score>bestScore){ bestScore=score; best=el; }
                    }
                }
                return best;
            }

            function parseCenterText(){
                var t = '';
                try { t = (window.centerDisplay && window.centerDisplay.textContent) ? window.centerDisplay.textContent.trim() : ''; } catch(e) { t=''; }
                if(!t){ window.isGameActive=false; window.roundCountdownSeconds=null; return; }
                var m = t.match(/^(\\d+(?:\\.\\d+)?)x$/i);
                if(m){
                    var v = parseFloat(m[1]);
                                                if(v>=1 && v<=10000){
                        window.currentMultiplier = v; window.lastMultiplierText = m[0]; window._lastMultChange = performance.now();
                        return;
                    }
                }
                var c = null;
                if(/^\\d{1,2}$/.test(t)){ c = parseFloat(t); }
                else { var cm = t.toLowerCase().match(/(\\d+(?:\\.\\d+)?)\\s*s/); if(cm) c = parseFloat(cm[1]); }
                if(c!=null && c>=0 && c<=60){ window.roundCountdownSeconds = c; }
            }

            function loop(){
                var now=performance.now();
                if(now - window.lastScanAt > 100){
                    window.lastScanAt = now;
                    var el = findKnownMultiplierElement();
                    if(!el) el = scanForElement();
                    if(el && el !== window.multiplierElement){
                        window.multiplierElement = el; window._dirty = true;
                    }
                    if(!window.multiplierElement){
                        var cd = scanForCountdown();
                        if(cd){ window.countdownElement = cd.el; window.roundCountdownSeconds = cd.val; }
                    }
                    if(!window.centerDisplay){
                        window.centerDisplay = scanForCenterDisplay();
                    }
                }
                var data = lightweightRead();
                if(data){
                    if(data.t !== window.lastMultiplierText){
                        window.currentMultiplier = data.v; window.lastMultiplierText = data.t; window.isGameActive = true; window.roundCountdownSeconds = null;
                        window._lastMultChange = now;
                    }
                } else {
                    // VERY aggressive reset - clear multiplier immediately when no fresh data
                    if((now - window._lastMultChange) > 800 && window.currentMultiplier > 0){
                        window.currentMultiplier = 0; window.lastMultiplierText = ""; window.isGameActive = false;
                        // Force element re-scan
                        window.multiplierElement = null;
                        window.centerDisplay = null;
                    }
                }
                parseCenterText();
                window.multiplierRafId = requestAnimationFrame(loop);
            }
            loop();
            """
            
            self.driver.execute_script(script)
            print("✅ rAF multiplier tracker setup complete")
            return True
            
        except Exception as e:
            print(f"⚠️ Error setting up multiplier tracker: {e}")
            return False

def main():
    """Main function to run the bot"""
    print("\n🎰 Solpump Bot - Improved Version")
    print("="*50)
    
    bot = SolpumpBot()
    
    try:
        # Load historical data
        bot.load_historical_results()
        
        # Navigate to website
        bot.navigate_to_solpump()
        
        # Wait for user to login
        bot.wait_for_user_login()
        
        # Run monitoring mode
        while True:
            result = bot.monitor_mode()
            
            if result == "EXIT":
                break
            elif result == "RESTART":
                bot.driver.quit()
                bot = SolpumpBot()
                bot.navigate_to_solpump()
                bot.wait_for_user_login()
                continue
                
    except KeyboardInterrupt:
        print("\n👋 Exiting...")
    except Exception as e:
        print(f"❌ Error: {e}")
        try:
            bot.driver.quit()
        except:
            pass
    finally:
        try:
            bot.driver.quit()
        except:
            pass
        print("✅ Bot stopped")

if __name__ == "__main__":
    main()
