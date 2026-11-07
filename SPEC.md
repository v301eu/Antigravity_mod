# whisper_saver — specyfikacja funkcjonalna (wersja robocza v0.1)

> Dokument roboczy. Poprawiamy go iteracyjnie, dopóki nie będzie w pełni zgodny z oczekiwanym działaniem — dopiero potem zmieniamy kod.

## 0. Zasady nadrzędne (dotyczą wszystkich ikon)

1. **Wyłącznie pamięć RAM.** Rozszerzenie nie zapisuje na dysk żadnych plików tymczasowych: zrzutów ekranu, nagrań audio, plików WAV, notatek ani plików `.md`. Historia rozmowy głosowej istnieje tylko w pamięci procesu i znika po wysłaniu wiadomości lub zamknięciu VS Code. Jedynym dozwolonym dostępem do dysku jest **odczyt** historii bieżącego czatu (transkryptu) aktywnego pluginu, aby model pomocniczy znał kontekst tematu.
2. **Rozpoznawanie mowy lokalnie na CPU** — OpenAI Whisper `large-v3-turbo` (kwantyzacja q5_0) uruchomiony jako stały serwer w tle; model ładowany raz, bez ponownego wczytywania przy każdej wypowiedzi.
3. **Głosy TTS wyłącznie neuronowe, offline.** **Kategoryczny zakaz** używania starych głosów systemowych (*David Desktop*, *Zira Desktop*, *Paulina Desktop* i podobnych), również jako „awaryjnych”. Głos dobierany jest do języka rozpoznanego przez Whisper według kolejności:
   1. **naturalny głos Microsoftu** (3. generacja, offline, np. *Microsoft Ryan* dla angielskiego), jeśli jest zainstalowany dla danego języka;
   2. w przeciwnym razie **neuronowy głos Piper** dla danego języka (np. *MC Speech* / *Darkman* dla polskiego);
   3. jeśli nie ma żadnego — rozszerzenie proponuje instalację brakującego głosu (patrz §0.7), a **do tego czasu tekst jest tłumaczony na angielski i czytany głosem *Microsoft Ryan*** (głos domyślny, zawsze obecny).
4. **Model pomocniczy (tańszy) zależny od aktywnego pluginu** — służy do poprawy gramatyki, wzbogacenia słownictwa i prowadzenia dyskusji:

   | Plugin czatu | Model główny (drogi) | Model pomocniczy (tani) | Komenda kompaktowania |
   |---|---|---|---|
   | Antigravity | wybrany przez użytkownika | Gemini 3.8 Flash | `/compact` *(do weryfikacji)* |
   | Claude Code | wybrany przez użytkownika | Claude Sonnet | `/compact` |
   | Codex | wybrany przez użytkownika | GPT 6.1 Sol | `/compact` |
   | Grok (z Cursora, jeśli dostępny w VS Code) | wybrany przez użytkownika | *(do ustalenia)* | *(do ustalenia)* |

5. **Odporność na aktualizacje** — rozszerzenie nie może polegać na wewnętrznych, nieudokumentowanych elementach VS Code ani pluginów, które zmieniają się z każdą wersją; ścieżki do narzędzi CLI wyszukuje dynamicznie, a nazwy modeli i komend kompaktowania są konfigurowalne w ustawieniach.
6. **Każdy tekst po korekcie gramatycznej jest odczytywany przez TTS**, zanim (lub w chwili gdy) trafi na czat.
7. **Automatyczna instalacja głosów dla nowych użytkowników.** Rozszerzenie musi działać od razu u każdego, kto je zainstaluje, niezależnie od języka:
   - **Microsoft Ryan jest głosem domyślnym i obowiązkowym** — przy pierwszym uruchomieniu, jeśli go brakuje, rozszerzenie prowadzi do jego instalacji w pierwszej kolejności;
   - gdy Whisper rozpozna język, dla którego nie ma głosu (np. francuski, niemiecki), rozszerzenie wyświetla pytanie z kodem języka, np. *„Brak głosu dla języka **fr-FR**. Pobrać?”* — po potwierdzeniu pobiera głos Piper (jednorazowo, ok. 60 MB, do folderu rozszerzenia) i od razu go używa;
   - jeśli w tym momencie brakuje także Ryana, jedno potwierdzenie instaluje **oba głosy**;
   - dopóki głos danego języka nie jest zainstalowany (lub użytkownik odmówił), obowiązuje zasada §0.3.3 — tłumaczenie na angielski i odczyt głosem Ryan;
   - jeśli dla tego języka istnieje naturalny głos Microsoftu, rozszerzenie dodatkowo **otwiera ustawienia Narratora z propozycją jego instalacji** (Windows nie pozwala zainstalować go po cichu); po instalacji automatycznie przełącza się na głos Microsoftu.

---

## 1. Ikona **C** — wycinek ekranu z edycją (Canvas)

**Cel:** szybkie przygotowanie opisanego zrzutu fragmentu ekranu jako załącznika do czatu, bez śladu na dysku.

**Przebieg:**
1. Kliknięcie ikony **C** (lub skrót `Alt+C`) zamraża obraz ekranu i przyciemnia go; użytkownik zaznacza myszą prostokątny obszar do wycięcia.
2. Po zaznaczeniu obszaru okno wycinka pozostaje otwarte i udostępnia pasek narzędzi do adnotacji: **pióro**, **zakreślacz**, **strzałka**, **ramka**, **tekst**, wybór **koloru** i **grubości**, **cofnij** (`Ctrl+Z`) oraz **zaznacz ponownie**. Użytkownik może dowolnie rysować, poprawiać i opisywać wycinek.
3. Naciśnięcie **`Ctrl+C`** w oknie narzędzia wykonuje w jednym kroku:
   - spłaszczenie wycinka razem z adnotacjami do jednego obrazu,
   - **kompresję** — dłuższy bok skalowany do **maksymalnie 768 px** (mniejsze obrazy nie są powiększane),
   - **skopiowanie do schowka wyłącznie w pamięci RAM** (bez zapisu pliku),
   - **automatyczne zamknięcie** okna.
4. `Esc` anuluje operację bez zmiany zawartości schowka.
5. Rozszerzenie odnotowuje, że w bieżącej wiadomości jest załącznik — wpływa to na kompaktowanie (patrz §5).

---

## 2. Ikona **mikrofonu** — dyktowanie i współpraca głosowa z modelem pomocniczym

**Cel:** dyktowanie wiadomości w dowolnym języku, z opcjonalną dyskusją z tańszym modelem, który pilnuje kompletności i jakości polecenia, zanim trafi ono do drogiego modelu głównego.

**Dyktowanie:**
1. Kliknięcie ikony (lub `Alt+M`) włącza nasłuch; ponowne kliknięcie go kończy.
2. Whisper Turbo **automatycznie rozpoznaje język** każdej wypowiedzi; od tego języka zależą odpowiedzi modelu pomocniczego i wybór głosu TTS.
3. Rozpoznany tekst trafia do **pola wprowadzania tekstu czatu** aktywnego pluginu (bez wysyłania), dopóki użytkownik nie wypowie jednej z komend.

**Komenda głosowa „whisper over” — tryb dyskusji:**
1. Wypowiedź zakończona frazą **„whisper over”** przekazuje dotychczasowy szkic do modelu pomocniczego wraz z:
   - pełną bieżącą wymianą głosową (przechowywaną w RAM),
   - kontekstem całego bieżącego tematu odczytanym z historii czatu.
2. Model pomocniczy ocenia, czy użytkownik **nie pominął czegoś istotnego** lub nie pozostawił niejasności. Jeśli tak — formułuje **pytanie doprecyzowujące**, które:
   - pojawia się w polu wprowadzania tekstu,
   - jest **odczytywane głosem TTS** (Ryan po angielsku, naturalny głos polski po polsku itd.).
3. Użytkownik odpowiada głosem i ponownie kończy frazą „whisper over”. Model może dopytywać dalej, nieprzerwanie utrzymując ciągłość rozmowy.
4. Gdy polecenie jest kompletne, model pomocniczy **poprawia gramatykę, wzbogaca słownictwo**, zachowując pierwotny sens, odczytuje wynik przez TTS i **wysyła go na czat** do modelu głównego.

**Komenda głosowa „whisper enter” — wysyłka natychmiastowa:**
- Wymusza korektę gramatyczną i wzbogacenie słownictwa **bez dyskusji i bez zmiany znaczenia wypowiedzi**, odczyt TTS, a następnie **bezpośrednie wysłanie** na czat.

**Komenda głosowa dołączenia zrzutu** (np. „whisper screen”, „wklej zrzut”):
- Wkleja obraz ze schowka jako załącznik do bieżącej wiadomości (patrz §5).

---

## 3. Ikona **Play / Pauza** — odczyt odpowiedzi

**Cel:** wygodne odsłuchanie odpowiedzi modelu głównego bez patrzenia w ekran.

1. Kliknięcie ikony (lub `Alt+P`) odczytuje **całą ostatnią odpowiedź** modelu głównego z aktywnego czatu (lub zaznaczony tekst w edytorze, jeśli jest zaznaczenie).
2. Podczas odtwarzania ikona zmienia się w **Pauzę**; kolejne kliknięcie wstrzymuje, następne wznawia od miejsca zatrzymania.
3. Odtwarzanie jest zintegrowane z systemową kontrolą multimediów Windows, dzięki czemu **przycisk play/pauza na słuchawkach Bluetooth** steruje odczytem tak samo jak ikona.
4. Głos dobierany jest automatycznie do języka tekstu, zgodnie z zasadą §0.3.

---

## 4. Ikona **A** — tryb automatyczny

**Cel:** pełna praca „bez rąk” — rozszerzenie samo słucha i samo czyta.

Włączenie trybu **A** (kliknięcie lub `Alt+A`; stan ON sygnalizowany kolorem ikony) aktywuje jednocześnie:
1. **Automatyczne nasłuchiwanie mikrofonu** — detekcja mowy (VAD) sama rozpoczyna i kończy nagrywanie każdej wypowiedzi; nie trzeba klikać ikony mikrofonu. Komendy „whisper over” / „whisper enter” działają identycznie jak w §2.
2. **Automatyczny odczyt TTS** treści wprowadzanej w polu tekstowym (dyktowanej lub poprawionej przez model pomocniczy).

Niezależnie od trybu **A**, **domyślnie włączony** jest automatyczny odczyt każdej nowej odpowiedzi czatu głównego (drogiego modelu). Można go wyłączyć w ustawieniach.

---

## 5. Załączniki i automatyczne kompaktowanie

1. Każde dodanie załącznika do wiadomości — wklejenie wycinka z ikony **C**, zrzutu PrintScreen, pliku lub obrazu dołączonego komendą głosową — oznacza wiadomość jako „z załącznikiem”.
2. Po wysłaniu takiej wiadomości rozszerzenie czeka, aż model główny **zakończy odpowiedź**, i dopiero wtedy wysyła **komendę kompaktowania** właściwą dla aktywnego pluginu (tabela §0.4) jako **osobną wiadomość**. Dzięki temu obraz nie jest ponownie przesyłany w kolejnych zapytaniach i nie zużywa tokenów.
3. Komendy kompaktowania nie dopisuje się na końcu wiadomości z załącznikiem: plugin rozpoznaje komendę tylko wtedy, gdy cała wiadomość zaczyna się od `/`. Gdyby nawet zadziałała, skompaktowałaby rozmowę, zanim model zdąży przeanalizować obraz.

---

## 6. Otwarte pytania (do rozstrzygnięcia przed implementacją)

1. ~~**Kiedy dokładnie wywołać `/compact`?**~~ **Rozstrzygnięte** — osobna wiadomość po zakończeniu odpowiedzi modelu (patrz §5).
2. ~~**Polski głos naturalny offline.**~~ **Rozstrzygnięte** — Piper dopuszczony, gdy brak naturalnego głosu Microsoftu; brakujące głosy instalowane automatycznie (§0.3, §0.7).
   - 2a. ~~Pobieranie bez pytania czy po potwierdzeniu?~~ **Rozstrzygnięte** — pytanie z kodem języka, potem pobranie; Ryan domyślny (§0.3, §0.7).
   - 2c. *Nowe:* przy braku głosu tłumaczenie na angielski dotyczy **tylko odczytu TTS**, a na czat trafia tekst w oryginalnym języku — zgoda? (Alternatywa: na czat też idzie wersja angielska.)
   - 2b. *Nowe:* gdy w zdaniu mieszają się języki (polski z angielskimi terminami technicznymi), czytamy całość jednym głosem języka dominującego — zgoda?, no dobra to zostawimy piper, ważne aby nowy użytkownij instalujacy plugin whisper_saver miał automatycznie instalowane brakujące głosy, bo rayan cyz piper jest polski ale inni mogę potrzebowac innych głosów, francuski czy niemiecki itp.
3. **„Auto TTS w trakcie pisania” (§4.2)** — czy czytać każde zdanie zaraz po jego zakończeniu, czy cały tekst dopiero po dyktowaniu/korekcie?
4. **Pytanie modelu w polu wprowadzania** — gdy użytkownik zacznie odpowiadać, czy pytanie ma zostać **zastąpione** odpowiedzią, czy odpowiedź ma być **dopisana** pod pytaniem?
5. **Ikona C a wklejanie** — czy po `Ctrl+C` obraz ma być **automatycznie wklejony** do pola czatu, czy tylko trafić do schowka (wklejasz sam przez `Ctrl+V`)?
6. **Komenda anulowania** — czy dodać np. „whisper cancel” / „whisper stop”, która porzuca bieżącą dyskusję i czyści szkic?
7. **Mikrofon a słuchawki Bluetooth** — użycie mikrofonu słuchawek BT przełącza je w tryb zestawu głośnomówiącego (słaba jakość mono). Obecny kod blokuje mikrofony BT i nagrywa z mikrofonu wbudowanego/USB. Zostawiamy tak?
8. **Blokada głośników** — obecny kod odmawia odtwarzania TTS, gdy nie ma podłączonych słuchawek. Tego nie ma w Twoim opisie. Zostawić czy usunąć?
9. **Automatyczny commit i push po każdym zapisie pliku** — obecny kod to robi (stąd dziesiątki commitów „chore(auto)” i wypchnięty folder `.claude/`). Tego też nie ma w Twoim opisie. Proponuję usunąć.
10. **Mowa a TTS w trybie A** — czy mikrofon ma być wyciszany na czas odczytu TTS (aby nie rozpoznawał własnego głosu przy głośnikach), czy można przerwać odczyt, zaczynając mówić?
11. **Grok** — w VS Code nie ma obecnie zainstalowanego pluginu Grok; jaki model tani i jaką komendę kompaktowania przyjąć, gdy się pojawi?
12. **Strumieniowy Voice Chat (Whisper v3 turbo na CPU) w polu wprowadzania** — odkładamy na kolejny etap, zgodnie z ustaleniem.
