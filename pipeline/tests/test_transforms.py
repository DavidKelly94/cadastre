"""Conventions are the whole point of transforms.py, so the tests pin them."""

from __future__ import annotations

import numpy as np
import pytest

from cadastre.transforms import (
    ARKIT_TO_CV,
    K_from_list,
    arkit_to_cv,
    embed_se2,
    mat_from_cm,
    mat_to_cm,
    se2_to_mat,
    theta_from_se2,
    umeyama_2d,
    unproject,
)


def test_column_major_indexing_matches_the_format():
    # Element at row r, column c is index c*4 + r; translation at 12, 13, 14.
    values = list(range(16))
    m = mat_from_cm(values)
    assert m[0, 0] == 0
    assert m[1, 0] == 1
    assert m[0, 1] == 4
    assert m[3, 3] == 15
    assert m[0, 3] == 12
    assert m[1, 3] == 13
    assert m[2, 3] == 14


def test_matrix_round_trips():
    values = [float(v) * 0.5 for v in range(16)]
    assert mat_to_cm(mat_from_cm(values)) == values


def test_matrix_helpers_reject_wrong_sizes():
    with pytest.raises(ValueError, match="16 numbers"):
        mat_from_cm([1, 2, 3])
    with pytest.raises(ValueError, match="4x4"):
        mat_to_cm(np.eye(3))


def test_intrinsics_are_row_major():
    k = K_from_list([1451.2, 0, 960.4, 0, 1451.2, 720.1, 0, 0, 1])
    assert k[0, 0] == pytest.approx(1451.2)
    assert k[0, 2] == pytest.approx(960.4)
    assert k[1, 1] == pytest.approx(1451.2)
    assert k[1, 2] == pytest.approx(720.1)
    assert k[2, 2] == pytest.approx(1.0)
    with pytest.raises(ValueError, match="9 numbers"):
        K_from_list([1, 2, 3])


def test_arkit_to_cv_is_its_own_inverse():
    np.testing.assert_allclose(ARKIT_TO_CV @ ARKIT_TO_CV, np.eye(4), atol=1e-15)


def test_arkit_to_cv_flips_y_and_z_but_not_translation():
    t_wc = np.eye(4)
    t_wc[:3, 3] = [1.0, 2.0, 3.0]
    cv = arkit_to_cv(t_wc)
    # The camera's +y and +z columns flip; the translation column is untouched.
    np.testing.assert_allclose(cv[:3, 0], [1, 0, 0], atol=1e-15)
    np.testing.assert_allclose(cv[:3, 1], [0, -1, 0], atol=1e-15)
    np.testing.assert_allclose(cv[:3, 2], [0, 0, -1], atol=1e-15)
    np.testing.assert_allclose(cv[:3, 3], [1, 2, 3], atol=1e-15)


def test_unproject_reproject_is_an_identity():
    k = K_from_list([1451.2, 0, 960.4, 0, 1451.2, 720.1, 0, 0, 1])
    fx, fy = k[0, 0], k[1, 1]
    cx, cy = k[0, 2], k[1, 2]
    for u, v, d in [(0.0, 0.0, 1.0), (960.4, 720.1, 2.5), (1919.0, 1439.0, 0.75)]:
        p = unproject(u, v, d, k)
        # Back to pixels: the ARKit camera looks down -z, so depth is -p[2] and
        # the image y axis is -p[1].
        assert -p[2] == pytest.approx(d)
        assert (p[0] / d) * fx + cx == pytest.approx(u)
        assert (-p[1] / d) * fy + cy == pytest.approx(v)


def test_unproject_puts_the_principal_ray_on_the_axis():
    k = K_from_list([1451.2, 0, 960.4, 0, 1451.2, 720.1, 0, 0, 1])
    p = unproject(960.4, 720.1, 3.0, k)
    np.testing.assert_allclose(p, [0.0, 0.0, -3.0], atol=1e-12)


def test_se2_matches_the_documented_layout():
    theta = 0.3
    m = se2_to_mat(theta, 1.0, 2.0, 3.0)
    assert m[0, 0] == pytest.approx(np.cos(theta))
    assert m[0, 2] == pytest.approx(np.sin(theta))
    assert m[2, 0] == pytest.approx(-np.sin(theta))
    assert m[2, 2] == pytest.approx(np.cos(theta))
    assert m[1, 1] == pytest.approx(1.0)
    np.testing.assert_allclose(m[:3, 3], [1.0, 2.0, 3.0])
    np.testing.assert_allclose(m[3, :], [0, 0, 0, 1])


def test_se2_is_a_rotation_about_plus_y():
    # +90 degrees about +y takes +x to -z, and leaves +y alone.
    m = se2_to_mat(np.pi / 2, 0, 0, 0)
    np.testing.assert_allclose(m @ [1, 0, 0, 1], [0, 0, -1, 1], atol=1e-12)
    np.testing.assert_allclose(m @ [0, 1, 0, 1], [0, 1, 0, 1], atol=1e-12)


def test_theta_round_trips_through_the_matrix():
    for theta in [-2.5, -0.4, 0.0, 0.4, 2.5]:
        assert theta_from_se2(se2_to_mat(theta, 0, 0, 0)) == pytest.approx(theta)


def test_umeyama_recovers_a_known_transform():
    rng = np.random.default_rng(0)
    a = rng.uniform(-5, 5, size=(12, 2))
    theta = 0.7
    rot = np.array([[np.cos(theta), np.sin(theta)], [-np.sin(theta), np.cos(theta)]])
    t = np.array([3.25, -1.5])
    b = a @ rot.T + t

    rotation, translation, rms = umeyama_2d(a, b)
    np.testing.assert_allclose(rotation, rot, atol=1e-9)
    np.testing.assert_allclose(translation, t, atol=1e-9)
    assert rms == pytest.approx(0.0, abs=1e-9)


def test_umeyama_result_embeds_into_the_documented_se2():
    # The rotation umeyama produces, embedded at rows and columns 0 and 2, must
    # equal se2_to_mat for the same angle. This is the join between the two
    # documents and the one place a sign error would hide.
    theta = 0.7
    rng = np.random.default_rng(1)
    a = rng.uniform(-5, 5, size=(20, 2))
    rot = np.array([[np.cos(theta), np.sin(theta)], [-np.sin(theta), np.cos(theta)]])
    t = np.array([2.0, -0.5])
    b = a @ rot.T + t

    rotation, translation, _ = umeyama_2d(a, b)
    embedded = embed_se2(rotation, translation, ty=1.25)
    expected = se2_to_mat(theta, t[0], 1.25, t[1])
    np.testing.assert_allclose(embedded, expected, atol=1e-9)
    assert theta_from_se2(embedded) == pytest.approx(theta, abs=1e-9)


def test_embedded_transform_maps_session_points_to_house_points():
    theta = -1.1
    rng = np.random.default_rng(2)
    a = rng.uniform(-4, 4, size=(8, 2))
    rot = np.array([[np.cos(theta), np.sin(theta)], [-np.sin(theta), np.cos(theta)]])
    t = np.array([-2.0, 6.5])
    b = a @ rot.T + t

    rotation, translation, _ = umeyama_2d(a, b)
    t_hs = embed_se2(rotation, translation)
    for (ax, az), (bx, bz) in zip(a, b, strict=True):
        mapped = t_hs @ [ax, 0.0, az, 1.0]
        assert mapped[0] == pytest.approx(bx, abs=1e-9)
        assert mapped[2] == pytest.approx(bz, abs=1e-9)


def test_umeyama_reports_residuals_rather_than_absorbing_them():
    # Scale is not fitted: a 10% larger point set must show up as residual, not
    # be silently soaked up, because the phone's own scale is metric.
    a = np.array([[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]])
    b = a * 1.1
    _, _, rms = umeyama_2d(a, b)
    assert rms > 0.01


def test_umeyama_stays_a_rotation_for_collinear_points():
    a = np.array([[0.0, 0.0], [1.0, 0.0], [2.0, 0.0], [3.0, 0.0]])
    b = np.array([[0.0, 0.0], [0.0, 1.0], [0.0, 2.0], [0.0, 3.0]])
    rotation, _, _ = umeyama_2d(a, b)
    assert np.linalg.det(rotation) == pytest.approx(1.0, abs=1e-9)
    np.testing.assert_allclose(rotation @ rotation.T, np.eye(2), atol=1e-9)


def test_umeyama_validates_its_input():
    with pytest.raises(ValueError, match="same shape"):
        umeyama_2d(np.zeros((3, 2)), np.zeros((4, 2)))
    with pytest.raises(ValueError, match=r"\(n, 2\)"):
        umeyama_2d(np.zeros((3, 3)), np.zeros((3, 3)))
    with pytest.raises(ValueError, match="at least two"):
        umeyama_2d(np.zeros((1, 2)), np.zeros((1, 2)))
