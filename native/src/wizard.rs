use crate::{
    core::{self, Event, Machine},
    input::TextInput,
    windows,
};
use gpui::{div, prelude::*, px, rgb, *};
use std::{
    sync::mpsc::{self, Receiver},
    time::{Duration, Instant},
};
use zeroize::Zeroizing;

actions!(
    onboarding,
    [
        Advance,
        Back,
        Restart,
        ToggleMotion,
        CopyReport,
        Refresh,
        TabNext,
        TabPrevious
    ]
);
#[derive(Clone, Copy, PartialEq, Debug)]
enum Page {
    Intro,
    Key,
    Review,
}
#[derive(Clone, Copy, PartialEq, Debug)]
enum Phase {
    Loading,
    Ready,
    Working,
    Done,
    Error,
}
enum Update {
    Inspected(Result<Machine, String>),
    Progress(Event),
    Finished(Result<(), String>),
}
pub struct Wizard {
    machine: Option<Machine>,
    input: Entity<TextInput>,
    focus: FocusHandle,
    page: Page,
    phase: Phase,
    message: String,
    events: Vec<Event>,
    updates: Receiver<Update>,
    sender: mpsc::Sender<Update>,
    started: Instant,
    motion: bool,
}
pub fn bind_keys(cx: &mut App) {
    cx.bind_keys([
        KeyBinding::new("tab", TabNext, Some("Wizard")),
        KeyBinding::new("shift-tab", TabPrevious, Some("Wizard")),
        KeyBinding::new("escape", Back, Some("Wizard")),
        KeyBinding::new("alt-n", Restart, Some("Wizard")),
        KeyBinding::new("alt-m", ToggleMotion, Some("Wizard")),
        KeyBinding::new("alt-c", CopyReport, Some("Wizard")),
        KeyBinding::new("alt-r", Refresh, Some("Wizard")),
    ]);
}
impl Wizard {
    pub fn focus(&self, window: &mut Window, cx: &mut Context<Self>) {
        window.focus(&self.focus, cx);
    }
    pub fn new(cx: &mut Context<Self>) -> Self {
        let (sender, updates) = mpsc::channel();
        let mut this = Self {
            machine: None,
            input: cx.new(TextInput::new),
            focus: cx.focus_handle(),
            page: Page::Intro,
            phase: Phase::Loading,
            message: "이 기기의 네트워크와 원격 접속 상태를 확인합니다.".into(),
            events: vec![],
            updates,
            sender,
            started: Instant::now(),
            motion: true,
        };
        this.inspect(cx);
        cx.spawn(async move |entity, cx| {
            loop {
                cx.background_executor()
                    .timer(Duration::from_millis(100))
                    .await;
                if entity
                    .update(cx, |this, cx| {
                        let changed = this.poll();
                        if changed || this.phase == Phase::Working {
                            cx.notify();
                        }
                    })
                    .is_err()
                {
                    break;
                }
            }
        })
        .detach();
        this
    }
    fn inspect(&mut self, cx: &mut Context<Self>) {
        self.phase = Phase::Loading;
        self.page = Page::Intro;
        self.events.clear();
        self.input.update(cx, |input, _| input.reset());
        let sender = self.sender.clone();
        std::thread::spawn(move || {
            let result = windows::inspect().map_err(|e| core::redact(&e.to_string()));
            let _ = sender.send(Update::Inspected(result));
        });
    }
    fn poll(&mut self) -> bool {
        let mut changed = false;
        while let Ok(update) = self.updates.try_recv() {
            changed = true;
            match update {
                Update::Inspected(Ok(machine)) => {
                    self.machine = Some(machine);
                    if self.phase != Phase::Done {
                        self.phase = Phase::Ready;
                    }
                    self.message = "현재 상태를 인프라 관리자에게 전달할 수 있습니다.".into();
                }
                Update::Inspected(Err(e)) | Update::Finished(Err(e)) => {
                    self.page = Page::Intro;
                    self.message = core::redact(&e);
                    self.phase = Phase::Error;
                }
                Update::Progress(e) => {
                    self.message = e.message.clone();
                    self.events.push(e);
                }
                Update::Finished(Ok(())) => {
                    self.phase = Phase::Done;
                    self.page = Page::Intro;
                    let sender = self.sender.clone();
                    std::thread::spawn(move || {
                        let _ = sender.send(Update::Inspected(
                            windows::inspect().map_err(|e| core::redact(&e.to_string())),
                        ));
                    });
                }
            }
        }
        changed
    }
    fn advance(&mut self, _: &Advance, window: &mut Window, cx: &mut Context<Self>) {
        if self.phase != Phase::Ready {
            return;
        }
        match self.page {
            Page::Intro => {
                self.page = Page::Key;
                window.focus(&self.input.focus_handle(cx), cx);
            }
            Page::Key => {
                if let Err(e) = core::validate_key(self.input.read(cx).value()) {
                    self.message = e.to_string();
                    cx.notify();
                    return;
                }
                self.page = Page::Review;
                self.message = "설정할 내용을 확인해 주세요.".into();
                window.focus(&self.focus, cx);
            }
            Page::Review => {
                let key = match core::validate_key(self.input.read(cx).value()) {
                    Ok(key) => Zeroizing::new(key),
                    Err(e) => {
                        self.message = e.to_string();
                        cx.notify();
                        return;
                    }
                };
                self.input.update(cx, |i, _| i.reset());
                self.phase = Phase::Working;
                self.started = Instant::now();
                self.events.clear();
                self.message =
                    "필요한 관리자 권한을 요청합니다. Windows 승인 창을 확인해 주세요.".into();
                let machine = self.machine.clone().unwrap();
                let sender = self.sender.clone();
                std::thread::spawn(move || {
                    let result = windows::onboard(machine, key, |e| {
                        let _ = sender.send(Update::Progress(e));
                    })
                    .map_err(|e| core::redact(&e.to_string()));
                    let _ = sender.send(Update::Finished(result));
                });
            }
        }
        cx.notify();
    }
    fn back(&mut self, _: &Back, window: &mut Window, cx: &mut Context<Self>) {
        if self.phase == Phase::Ready {
            self.page = match self.page {
                Page::Review => Page::Key,
                _ => Page::Intro,
            };
            window.focus(&self.focus, cx);
            cx.notify();
        }
    }
    fn restart(&mut self, _: &Restart, window: &mut Window, cx: &mut Context<Self>) {
        if matches!(self.phase, Phase::Ready | Phase::Done | Phase::Error) && self.machine.is_some()
        {
            self.phase = Phase::Ready;
            self.page = Page::Key;
            self.input.update(cx, |i, _| i.reset());
            self.message =
                "새 등록 키가 필요합니다. 최종 승인 후 기존 Tailscale 설정을 모두 삭제합니다."
                    .into();
            window.focus(&self.input.focus_handle(cx), cx);
            cx.notify();
        }
    }
    fn toggle_motion(&mut self, _: &ToggleMotion, _: &mut Window, cx: &mut Context<Self>) {
        self.motion = !self.motion;
        cx.notify();
    }
    fn copy(&mut self, _: &CopyReport, _: &mut Window, cx: &mut Context<Self>) {
        let fallback = vec![Event {
            stage: format!("{:?}", self.phase),
            message: self.message.clone(),
            ..Default::default()
        }];
        let events = if self.events.is_empty() {
            &fallback
        } else {
            &self.events
        };
        let report = core::report(events, self.machine.as_ref().map_or("확인 전", |m| &m.user));
        let status = self
            .machine
            .as_ref()
            .map(core::machine_report)
            .unwrap_or_default();
        cx.write_to_clipboard(ClipboardItem::new_string(core::redact(&format!(
            "{status}\n{report}"
        ))));
        self.message = "지원 리포트를 복사했습니다. 인프라 관리자에게 전달해 주세요.".into();
        cx.notify();
    }
    fn refresh(&mut self, _: &Refresh, _: &mut Window, cx: &mut Context<Self>) {
        if matches!(self.phase, Phase::Ready | Phase::Done | Phase::Error)
            && self.page == Page::Intro
        {
            self.inspect(cx);
            cx.notify();
        }
    }
    fn button(
        &self,
        id: &'static str,
        label: impl Into<SharedString>,
        action: impl Action,
        secondary: bool,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let label = label.into();
        let keyboard_action = action.boxed_clone();
        div()
            .id(id)
            .accessibility_id(id)
            .role(Role::Button)
            .aria_label(label.clone())
            .focusable()
            .tab_stop(true)
            .cursor_pointer()
            .px_5()
            .py_3()
            .rounded_lg()
            .border_1()
            .border_color(rgb(if secondary { 0xe3e8ef } else { 0x2563eb }))
            .bg(rgb(if secondary { 0xffffff } else { 0x2563eb }))
            .text_color(rgb(if secondary { 0x17212f } else { 0xffffff }))
            .text_size(px(15.))
            .font_weight(FontWeight::SEMIBOLD)
            .focus_visible(|s| s.border_color(rgb(0x60a5fa)).border_2())
            .hover(|s| s.opacity(0.85))
            .on_key_down(cx.listener(move |_, event: &KeyDownEvent, window, cx| {
                if !event.is_held && matches!(event.keystroke.key.as_str(), "enter" | "space") {
                    window.dispatch_action(keyboard_action.boxed_clone(), cx);
                    cx.stop_propagation();
                }
            }))
            .on_click(
                cx.listener(move |_, _, window, cx| {
                    window.dispatch_action(action.boxed_clone(), cx)
                }),
            )
            .child(label)
    }
}
impl Render for Wizard {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let title = match self.phase {
            Phase::Done => "원격 지원을 받을 준비가 됐어요.",
            Phase::Error => "잠시 멈췄어요. 함께 확인해요.",
            Phase::Working => "차근차근 준비하고 있어요.",
            _ => match self.page {
                Page::Intro => "이 기기의 현재 상태예요.",
                Page::Key => "연결 정보를 알려주세요.",
                Page::Review => "시작 전에 확인해 주세요.",
            },
        };
        let mut body = div()
            .flex()
            .flex_col()
            .gap_3()
            .flex_1()
            .child(
                div()
                    .id("heading")
                    .accessibility_id("heading")
                    .role(Role::Heading)
                    .aria_level(1)
                    .aria_label(title)
                    .text_size(px(27.))
                    .font_weight(FontWeight::SEMIBOLD)
                    .child(title),
            )
            .child(
                div()
                    .id("status")
                    .accessibility_id("status")
                    .role(Role::Status)
                    .aria_label(self.message.clone())
                    .text_size(px(14.))
                    .text_color(rgb(if self.phase == Phase::Error {
                        0xa33a2b
                    } else {
                        0x536174
                    }))
                    .child(self.message.clone()),
            );
        if self.phase == Phase::Ready {
            let machine = self.machine.as_ref().unwrap();
            match self.page {
                Page::Intro => {
                    if !machine.connected {
                        body = body.child(self.button("begin", "시작하기  ↵", Advance, false, cx));
                    }
                }
                Page::Key => {
                    body = body.child(
                        panel()
                            .child(format!("이 기기의 계정: {}", machine.user))
                            .child(if machine.connected {
                                format!(
                                    "현재 연결: {} · {}",
                                    machine.tailnet.as_deref().unwrap_or("확인 전"),
                                    machine.ip.as_deref().unwrap_or("확인 전")
                                )
                            } else {
                                "아직 Tailscale에 연결되지 않았어요.".into()
                            }),
                    );
                    body = body
                        .child("Tailscale 등록 키")
                        .child(self.input.clone())
                        .child(
                            div()
                                .text_size(px(12.))
                                .text_color(rgb(0x536174))
                                .child("24시간 유효 · 일회용 · 기기에 저장하지 않음"),
                        );
                    body = body.child(spacer()).child(
                        div()
                            .flex()
                            .gap_3()
                            .child(self.button("back", "뒤로", Back, true, cx))
                            .child(self.button("next", "다음  ↵", Advance, false, cx)),
                    );
                }
                Page::Review => {
                    let connection =
                        "기존 Tailscale 연결·저장된 계정·설정을 모두 삭제하고 입력한 새 키로 등록";
                    const SCOPE: &str = "모든 네트워크에서 SSH 접속(TCP 22번)을 허용해요.";
                    body = body
                        .child(
                            panel()
                                .id("review-settings").accessibility_id("review-settings")
                                .role(Role::Group)
                                .aria_label(format!("SSH 접속 대상: {}. {connection}. Tailscale 최신 버전과 Windows SSH 서버 준비. 기본 관리자 공개키 두 개 등록.", machine.user))
                                .child(format!("SSH 접속 대상: {}", machine.user))
                                .child(connection)
                                .child("Tailscale 최신 버전과 Windows SSH 서버 준비")
                                .child("기본 관리자 공개키 두 개 등록"),
                        )
                        .child(
                            div()
                                .id("ssh-scope").accessibility_id("ssh-scope")
                                .role(Role::Label).aria_value(SCOPE)
                                .bg(rgb(0xfff7ed))
                                .text_color(rgb(0x8b4b18))
                                .p_4()
                                .rounded_lg()
                                .child(SCOPE),
                        )
                        .child(
                            "아래 버튼을 누르면 이 설정에 동의하고 Windows 승인 창으로 이동해요.",
                        )
                        .child(spacer())
                        .child(
                            div()
                                .flex()
                                .gap_3()
                                .child(self.button("back", "뒤로", Back, true, cx))
                                .child(self.button(
                                    "start",
                                    "동의하고 준비 시작  ↵",
                                    Advance,
                                    false,
                                    cx,
                                )),
                        );
                }
            }
        }
        if self.phase == Phase::Working {
            let stages = [
                ("update", "Tailscale 설치 · 업데이트"),
                ("logout", "기존 Tailscale 설정 삭제"),
                ("connect", "네트워크 연결"),
                ("ssh", "원격 접속 준비"),
                ("verify", "최종 확인"),
            ];
            let active = self.events.last().map(|e| e.stage.as_str()).unwrap_or("");
            let mut list = panel();
            for (id, label) in stages {
                let is_active = id == active;
                list = list.child(
                    div()
                        .when(is_active && self.motion, |s| {
                            s.opacity(
                                0.6 + 0.4
                                    * ((self.started.elapsed().as_secs_f32() * 3.).sin().abs()),
                            )
                        })
                        .text_color(rgb(if is_active { 0x2563eb } else { 0x536174 }))
                        .child(format!("{}  {label}", if is_active { "●" } else { "○" })),
                );
            }
            let seconds = self.started.elapsed().as_secs();
            body = body
                .child(list)
                .child(format!(
                    "경과 {}분 {}초 · 창을 닫지 말고 기다려 주세요.",
                    seconds / 60,
                    seconds % 60
                ))
                .child("다운로드와 설치에 몇 분 걸릴 수 있어요. 문제가 생기면 한 번 더 시도해요.")
                .child(spacer())
                .child(self.button(
                    "motion",
                    if self.motion {
                        "모션 줄이기 (Alt+M)"
                    } else {
                        "모션 켜기 (Alt+M)"
                    },
                    ToggleMotion,
                    true,
                    cx,
                ));
        }
        if matches!(self.phase, Phase::Ready | Phase::Done | Phase::Error)
            && self.page == Page::Intro
        {
            if let Some(machine) = &self.machine {
                let status = core::machine_report(machine);
                body = body.child(
                    panel().child(
                        div()
                            .id("machine-status")
                            .accessibility_id("machine-status")
                            .role(Role::Label)
                            .aria_value(status.clone())
                            .child(
                                div()
                                    .id("report")
                                    .accessibility_id("report")
                                    .role(Role::Label)
                                    .aria_value(status.clone())
                                    .child(status),
                            ),
                    ),
                );
            }
            body = body
                .child(self.button("restart", "강제로 다시 시작하기 (Alt+N)", Restart, true, cx))
                .child("관리자에게 이 리포트를 전달해 실제 원격 접속을 확인해 주세요.")
                .child(spacer())
                .child(
                    div()
                        .flex()
                        .gap_3()
                        .child(self.button(
                            "refresh",
                            "현재 상태 다시 확인 (Alt+R)",
                            Refresh,
                            true,
                            cx,
                        ))
                        .child(self.button(
                            "copy-report",
                            "관리자에게 리포트 복사 (Alt+C)",
                            CopyReport,
                            false,
                            cx,
                        )),
                );
        }

        div()
            .id("wizard")
            .role(Role::Application)
            .aria_label("Kiloworks Onboarding")
            .key_context("Wizard")
            .on_key_down(cx.listener(|this, event: &KeyDownEvent, window, cx| {
                // Holding Enter must not advance through review into elevation.
                if !event.is_held && event.keystroke.key == "enter" {
                    this.advance(&Advance, window, cx);
                    cx.stop_propagation();
                }
            }))
            .track_focus(&self.focus)
            .on_action(cx.listener(|_, _: &TabNext, w, cx| w.focus_next(cx)))
            .on_action(cx.listener(|_, _: &TabPrevious, w, cx| w.focus_prev(cx)))
            .on_action(cx.listener(Self::advance))
            .on_action(cx.listener(Self::back))
            .on_action(cx.listener(Self::restart))
            .on_action(cx.listener(Self::toggle_motion))
            .on_action(cx.listener(Self::copy))
            .on_action(cx.listener(Self::refresh))
            .size_full()
            .bg(rgb(0xf6f8fb))
            .text_color(rgb(0x17212f))
            .font_family("Pretendard")
            .text_size(px(15.))
            .flex()
            .flex_col()
            .items_center()
            .p_6()
            .gap_4()
            .child(
                div()
                    .w(px(700.))
                    .flex()
                    .justify_between()
                    .child(
                        div()
                            .font_weight(FontWeight::SEMIBOLD)
                            .child("kiloworks / onboarding"),
                    )
                    .child(div().text_size(px(12.)).child("Windows · x64 / ARM64")),
            )
            .child(
                div()
                    .w(px(700.))
                    .flex_1()
                    .flex()
                    .flex_col()
                    .gap_5()
                    .p_6()
                    .bg(rgb(0xffffff))
                    .border_1()
                    .border_color(rgb(0xe3e8ef))
                    .rounded_xl()
                    .child(
                        div()
                            .text_size(px(13.))
                            .text_color(rgb(0x2563eb))
                            .child("① 연결 정보    →    ② 설정 확인    →    ③ 기기 준비"),
                    )
                    .child(body),
            )
            .child(
                div()
                    .text_size(px(12.))
                    .text_color(rgb(0x536174))
                    .child(concat!(
                        "v",
                        env!("CARGO_PKG_VERSION"),
                        " · 미서명 프리뷰 · 원격 접속 확인은 관리자와 함께 진행해 주세요."
                    )),
            )
    }
}
fn panel() -> Div {
    div()
        .flex()
        .flex_col()
        .gap_2()
        .p_4()
        .bg(rgb(0xf6f8fb))
        .rounded_lg()
}
fn spacer() -> Div {
    div().flex_1()
}
