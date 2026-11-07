<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Подарок 🎁</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            background: linear-gradient(145deg, #ffb6c1 0%, #ff69b4 50%, #ff1493 100%);
            font-family: 'Segoe UI', Roboto, system-ui, sans-serif;
            overflow: hidden;
        }
        .container {
            position: relative;
            width: 100%;
            height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
        }
        .gift {
            font-size: 160px;
            cursor: pointer;
            filter: drop-shadow(0 15px 25px rgba(180, 0, 80, 0.5));
            transition: transform 0.3s ease, filter 0.3s ease;
            user-select: none;
            z-index: 20;
            animation: float 3s ease-in-out infinite;
        }
        .gift:hover { transform: scale(1.1) rotate(5deg); filter: drop-shadow(0 20px 35px rgba(180, 0, 80, 0.8)); }
        .gift:active { transform: scale(0.95); }
        @keyframes float { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-15px); } }

        .subtitle-stage {
            position: absolute;
            bottom: 40px;
            left: 50%;
            transform: translateX(-50%);
            width: 90%;
            max-width: 800px;
            height: 280px;
            pointer-events: none;
            z-index: 10;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: flex-end;
            gap: 8px;
            overflow: hidden;
        }
        .subtitle {
            font-size: 1.8rem;
            font-weight: 900;
            text-align: center;
            color: white;
            text-shadow: 3px 3px 0 #d1006b, 6px 6px 0 rgba(0,0,0,0.15);
            letter-spacing: 1px;
            line-height: 1.3;
            opacity: 0;
            animation: flyOut 0.6s cubic-bezier(0.22, 1.4, 0.36, 1) forwards;
            white-space: nowrap;
        }
        @keyframes flyOut {
            0% { opacity: 0; transform: translateY(140px) scale(0.4) rotate(-8deg); }
            60% { opacity: 1; transform: translateY(-12px) scale(1.06) rotate(2deg); }
            100% { opacity: 1; transform: translateY(0) scale(1) rotate(0); }
        }
        .subtitle.ya { color: #ffe4f0; text-shadow: 3px 3px 0 #b3005e, 6px 6px 0 rgba(0,0,0,0.15); }
        .subtitle.ty { color: #fff0f5; text-shadow: 3px 3px 0 #8b004a, 6px 6px 0 rgba(0,0,0,0.15); }

        .hint {
            position: absolute;
            top: 30px;
            color: white;
            font-size: 1.2rem;
            opacity: 0.9;
            text-shadow: 1px 1px 4px rgba(0,0,0,0.4);
            letter-spacing: 2px;
            animation: pulse 2s infinite;
            z-index: 5;
        }
        @keyframes pulse { 0%, 100% { opacity: 0.6; } 50% { opacity: 1; } }

        @media (max-width: 600px) {
            .gift { font-size: 110px; }
            .subtitle { font-size: 1.15rem; white-space: normal; padding: 0 10px; }
            .subtitle-stage { bottom: 20px; height: 320px; }
            .hint { font-size: 0.9rem; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="hint" id="hint">👆 Нажми на подарок</div>
        <div class="gift" id="giftBtn">🎁</div>
        <div class="subtitle-stage" id="subtitleStage"></div>
    </div>

    <audio id="audioPlayer" src="ff2e52f5abb6f71f08ef369afdda1dc8.mp3" preload="auto"></audio>

    <script>
    (function() {
        const gift = document.getElementById('giftBtn');
        const stage = document.getElementById('subtitleStage');
        const hint = document.getElementById('hint');
        const audio = document.getElementById('audioPlayer');

        let started = false;

        // === НАСТРОЙКИ ВОСПРОИЗВЕДЕНИЯ ===
        // С какой секунды начинать (сразу с фразы «ты моя шалава»)
        const START_AT = 0;   // ← поменяйте на нужную секунду
        // На какой секунде закончить (после «да я твоя блядина»)
        const END_AT   = 22;  // ← поменяйте на нужную секунду

        // === СУБТИТРЫ ===
        // Тайминги считаются ОТ НАЧАЛА воспроизведения (т.е. от START_AT).
        // Если хотите абсолютные — прибавьте START_AT.
        const cues = [
            { start: 0.5,  end: 3.0,  text: 'Я: ты моя шалава', type: 'ya' },
            { start: 3.2,  end: 5.8,  text: 'Я: ты моя блядина', type: 'ya' },
            { start: 6.2,  end: 9.0,  text: 'Ты: да я твоя шалава', type: 'ty' },
            { start: 9.2,  end: 12.0, text: 'Ты: да я твоя блядина', type: 'ty' },
            { start: 12.5, end: 15.0, text: 'Я: ты моя шалава', type: 'ya' },
            { start: 15.2, end: 18.0, text: 'Я: ты моя блядина', type: 'ya' },
            { start: 18.5, end: 21.5, text: 'Ты: да я твоя шалава, да я твоя блядина', type: 'ty' }
        ];

        // Приводим тайминги субтитров к абсолютному времени файла
        const absoluteCues = cues.map(c => ({
            start: c.start + START_AT,
            end:   c.end   + START_AT,
            text:  c.text,
            type:  c.type
        }));

        function syncSubtitles() {
            const t = audio.currentTime;

            // Удаляем просроченные
            Array.from(stage.children).forEach(child => {
                const end = parseFloat(child.dataset.end);
                if (t > end + 0.3) child.remove();
            });

            // Показываем активные
            absoluteCues.forEach(cue => {
                if (t >= cue.start && t <= cue.end) {
                    const exists = Array.from(stage.children).some(
                        child => child.textContent === cue.text
                    );
                    if (!exists) {
                        const el = document.createElement('div');
                        el.className = `subtitle ${cue.type}`;
                        el.textContent = cue.text;
                        el.dataset.end = cue.end;
                        stage.appendChild(el);
                        if (stage.children.length > 3) stage.removeChild(stage.children[0]);
                    }
                }
            });

            // === СТОП В КОНЦЕ ===
            if (t >= END_AT) {
                audio.pause();
                audio.removeEventListener('timeupdate', syncSubtitles);
            }
        }

        // === ЗАПУСК ===
        function start() {
            if (started) return;
            started = true;
            hint.style.display = 'none';
            gift.style.animation = 'none';
            gift.style.transform = 'scale(0.8)';
            setTimeout(() => { gift.style.transform = 'scale(1)'; }, 300);

            stage.innerHTML = '';
            audio.currentTime = START_AT;

            const playPromise = audio.play();
            if (playPromise !== undefined) {
                playPromise.catch(e => {
                    console.warn('Автозапуск заблокирован, нажмите ещё раз.', e);
                    started = false;
                });
            }
            audio.addEventListener('timeupdate', syncSubtitles);
        }

        gift.addEventListener('click', start);
        gift.addEventListener('touchstart', (e) => { e.preventDefault(); start(); }, { passive: false });
    })();
    </script>
</body>
</html>
