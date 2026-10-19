#![cfg_attr(target_os = "windows", windows_subsystem = "windows")]
mod core;
mod input;
mod windows;
mod wizard;

use gpui::{App, AppContext, Bounds, WindowBounds, WindowOptions, px, size};
use gpui_platform::application;
use std::{borrow::Cow, time::Duration};

fn main() {
    std::panic::set_hook(Box::new(|info| {
        eprintln!("{}", core::redact(&info.to_string()))
    }));
    application().run(|cx: &mut App| {
        cx.text_system()
            .add_fonts(vec![
                Cow::Borrowed(include_bytes!("../../assets/fonts/Pretendard-Regular.otf")),
                Cow::Borrowed(include_bytes!("../../assets/fonts/Pretendard-SemiBold.otf")),
            ])
            .expect("Pretendard 폰트를 불러올 수 없습니다.");
        input::bind_keys(cx);
        wizard::bind_keys(cx);
        let bounds = Bounds::centered(None, size(px(1000.), px(720.)), cx);
        cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                window_min_size: Some(size(px(860.), px(720.))),
                titlebar: Some(gpui::TitlebarOptions {
                    title: Some("Kiloworks Onboarding".into()),
                    ..Default::default()
                }),
                ..Default::default()
            },
            |window, cx| {
                let view = cx.new(wizard::Wizard::new);
                view.update(cx, |v, cx| v.focus(window, cx));
                view
            },
        )
        .expect("앱 창을 열 수 없습니다.");
        cx.on_window_closed(|cx, _| {
            if cx.windows().is_empty() {
                cx.quit();
            }
        })
        .detach();
        cx.activate(true);
        if std::env::args().any(|a| a == "--smoke-gui") {
            cx.spawn(async move |cx| {
                cx.background_executor().timer(Duration::from_secs(5)).await;
                cx.update(|cx| cx.quit());
            })
            .detach();
        }
    });
}
