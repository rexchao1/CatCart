void main() {
    float x = v_tex_coord.x - 0.5;
    float y = v_tex_coord.y;
    float horizon = u_horizon;
    float player = u_player;

    float roadHalf;
    if (y < horizon) {
        float f = clamp(y / max(horizon, 0.001), 0.0, 1.0);
        roadHalf = mix(u_roadBot, u_roadTop, f);
    } else {
        float f = clamp((y - horizon) / max(1.0 - horizon, 0.001), 0.0, 1.0);
        roadHalf = mix(u_roadTop, u_skyGap, f);
    }

    float t = (y - horizon) / min(player - horizon, -0.001);
    float aFar = 1.0 / u_zFar;
    float aNear = 1.0 / u_zNear;
    float a = aFar + t * (aNear - aFar);
    a = max(a, 0.12);
    float z = 1.0 / a;

    float inLane = step(abs(x), roadHalf);

    if (y >= horizon && inLane > 0.5) {
        gl_FragColor = vec4(0.0);
        return;
    }

    vec4 col;
    if (inLane > 0.5) {
        vec2 uv;
        uv.x = x / z * u_gRepeat + 0.5;
        uv.y = u_scroll / z;
        col = texture2D(u_texture, fract(uv));
    } else {
        vec2 uv;
        uv.x = u_scroll / z * u_wRepeat;
        uv.y = (y / z) * u_wUp + abs(x) * 0.4;
        col = texture2D(u_wall, fract(uv));
    }

    float haze = smoothstep(horizon - 0.14, horizon + 0.03, y);
    vec3 fog = vec3(u_hazeR, u_hazeG, u_hazeB);
    col.rgb = mix(col.rgb, fog, haze * 0.65);

    float alpha = 1.0;
    if (y > horizon) {
        alpha = mix(1.0, 0.15, haze);
    } else {
        alpha = mix(1.0, 0.55, haze * inLane);
    }

    gl_FragColor = vec4(col.rgb * alpha, alpha);
}
