package com.chef25.mobile.nodespike;

import android.app.Dialog;
import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/** Launcher-owned modal: no platform alert, button or input appearance. */
final class ChefDialog extends Dialog {
    private final LinearLayout stack;
    private final LinearLayout actions;
    ChefDialog(Context context, String title, String message) {
        super(context);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        setCanceledOnTouchOutside(true);
        ScrollView scroll = new ScrollView(context);
        scroll.setBackground(shape(0xfffffdf9, 20, 0xffe6e3d9));
        scroll.setClipToOutline(true);
        stack = new LinearLayout(context);
        stack.setOrientation(LinearLayout.VERTICAL);
        stack.setPadding(dp(24), dp(24), dp(24), dp(24));
        scroll.addView(stack);
        TextView heading = new TextView(context);
        heading.setText(title);
        heading.setTextSize(20);
        heading.setTextColor(0xff30332c);
        heading.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        if (android.os.Build.VERSION.SDK_INT >= 28) heading.setAccessibilityHeading(true);
        stack.addView(heading);
        TextView body = new TextView(context);
        body.setText(message);
        body.setTextSize(14);
        body.setTextColor(0xff747869);
        body.setLineSpacing(dp(4), 1);
        LinearLayout.LayoutParams bodyParams = row();
        bodyParams.topMargin = dp(12);
        stack.addView(body, bodyParams);
        actions = new LinearLayout(context);
        actions.setGravity(Gravity.END);
        LinearLayout.LayoutParams actionParams = row();
        actionParams.topMargin = dp(24);
        stack.addView(actions, actionParams);
        setContentView(scroll);
        Window window = getWindow();
        window.setBackgroundDrawableResource(android.R.color.transparent);
        window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
        WindowManager.LayoutParams params = window.getAttributes();
        params.dimAmount = 0.38f;
        window.setAttributes(params);
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
            | WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN);
    }

    private int dp(int value) { return Math.round(value * getContext().getResources().getDisplayMetrics().density); }
    private LinearLayout.LayoutParams row() { return new LinearLayout.LayoutParams(-1, -2); }
    private GradientDrawable shape(int color, int radius, int border) {
        GradientDrawable shape = new GradientDrawable();
        shape.setColor(color);
        shape.setCornerRadius(dp(radius));
        shape.setStroke(dp(1), border);
        return shape;
    }
    private Button action(String title, boolean primary, Runnable callback) {
        Button button = new ChefButton(getContext());
        button.setText(title);
        button.setTextColor(primary ? Color.WHITE : 0xff30332c);
        button.setBackground(shape(primary ? 0xffec6541 : 0xfff3f1e9, 10,
            primary ? 0xffec6541 : 0xffe6e3d9));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, dp(48), 1);
        if (actions.getChildCount() > 0) params.leftMargin = dp(10);
        actions.addView(button, params);
        button.setOnClickListener(view -> { dismiss(); if (callback != null) callback.run(); });
        return button;
    }
    void notice(String label) { action(label, true, null); show(); }
    void confirm(String phrase, String label, Runnable callback) {
        EditText input = new ChefTextInput(getContext());
        input.setHint("请输入：" + phrase);
        input.setContentDescription("输入" + phrase);
        LinearLayout.LayoutParams params = row();
        params.topMargin = dp(20);
        stack.addView(input, stack.indexOfChild(actions), params);
        action("取消", false, null);
        Button confirm = action(label, true, () -> {
            if (phrase.contentEquals(input.getText())) callback.run();
        });
        confirm.setEnabled(false);
        input.addTextChangedListener(new TextWatcher() {
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            public void onTextChanged(CharSequence s, int start, int before, int count) {
                confirm.setEnabled(phrase.contentEquals(s));
            }
            public void afterTextChanged(Editable value) {}
        });
        show();
        stack.setFocusableInTouchMode(true);
        stack.requestFocus();
    }
    @Override public void show() {
        super.show();
        int width = Math.min(dp(360), getContext().getResources().getDisplayMetrics().widthPixels - dp(40));
        getWindow().setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT);
    }
}

/** Shared custom button baseline, independent of the system theme. */
final class ChefButton extends Button {
    ChefButton(Context context) {
        super(context);
        setAllCaps(false);
        setTextSize(14);
        setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        setGravity(Gravity.CENTER);
        setMinHeight(0);
        setMinimumHeight(0);
        setMinWidth(0);
        setMinimumWidth(0);
        setStateListAnimator(null);
        setBackgroundTintList(null);
    }
    @Override public void setEnabled(boolean enabled) {
        super.setEnabled(enabled);
        setAlpha(enabled ? 1f : 0.38f);
    }
}

final class ChefTextInput extends EditText {
    ChefTextInput(Context context) {
        super(context);
        float density = getResources().getDisplayMetrics().density;
        setSingleLine(true);
        setTextSize(14);
        setTextColor(0xff30332c);
        setHintTextColor(0xff848779);
        setHighlightColor(0xfff8e5d8);
        setPadding(Math.round(14 * density), Math.round(12 * density),
            Math.round(14 * density), Math.round(12 * density));
        setBackgroundTintList(null);
        android.graphics.drawable.StateListDrawable states = new android.graphics.drawable.StateListDrawable();
        for (boolean focused : new boolean[] {true, false}) {
            GradientDrawable background = new GradientDrawable();
            background.setColor(0xfffbf9f5);
            background.setCornerRadius(10 * density);
            background.setStroke(Math.round(density), focused ? 0xffec6541 : 0xffd6d2c5);
            states.addState(focused ? new int[] {android.R.attr.state_focused} : new int[] {}, background);
        }
        setBackground(states);
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            GradientDrawable cursor = new GradientDrawable();
            cursor.setColor(0xffec6541);
            cursor.setSize(Math.round(2 * density), Math.round(20 * density));
            setTextCursorDrawable(cursor);
        }
    }
}
